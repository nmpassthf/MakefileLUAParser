-- Author: nmpassthf (nmpassthf@gmail.com)
-- Date: 2024-04-20
-- Version: 0.1.0

-- 在使用此脚本的时候，请不要手动更改Makefile中的变量名，否则可能会导致解析错误
-- 请不要修改Makefile中的优化等级，修改优化等级请使用xmake.lua的target中修改set_optimize()



-- define a debug flag for this script
MAKEFILE_PARSER_DEBUG_FLAG = false



function main(makefile_locate)
  local function simplicate_str(s)
    -- is s is nil or only space? return ""
    if not s or s:match("^%s*$") then
      return ""
    end
    local res = s:match("^%s*(.-)%s*$")
    return res
  end

  local function isKVpattern(current_line)
    return current_line:match("[%a_-]+%s*(=)") ~= nil or current_line:match("[%a_-]+%s*(:=)") ~= nil or
        current_line:match("[%a_-]+%s*(+=)") ~= nil
  end
  local function parseKVpattern(current_kvtable, current_line)
    local key = nil
    local value = nil

    
    -- the line is a pattern like "Key = value"
    if current_line:match("[%a_-]+%s*(:=)") then
      key = current_line:match("([^:=]+)")
      value = current_line:match(":=+(.+)")
      -- remove key end space
      key = simplicate_str(key)
      value = simplicate_str(value)

      current_kvtable[key] = value
    elseif current_line:match("[%a_-]+%s*(+=)") then
      key = current_line:match("([^+=]+)")
      value = current_line:match("=+(.+)")
      -- remove key end space
      key = simplicate_str(key)
      value = simplicate_str(value)

      local current_value = current_kvtable[key]
      if not current_value then current_value = "" end
      current_kvtable[key] = current_value .. " " .. value
    elseif current_line:match("[%a_-]+%s*(=)") then
      key = current_line:match("([^=]+)")
      value = current_line:match("=(.+)")
      -- remove key end space
      key = simplicate_str(key)
      value = simplicate_str(value)

      current_kvtable[key] = value
    else
      print("Makefile Parse Error: parseKVpattern error: line is not a key-value pattern:" .. current_line)
    end
  end

  -- find the first makefile-key type (like:$(KEY)) return the KEY
  local function findFirstMakefileVarKey(s)
    local v = s:match("%$%(%s*([%a_-]+)%s*%)")
    return v
  end
  local function replaceFirstMakefileKey(s, key, value)
    if key:match("%-") then
      key = key:gsub("%-", "%%-")
    end
    local v = s:gsub("%$%(%s*" .. key .. "%s*%)", value)
    return v
  end

  local function isEndifExpr(line)
    return line:match("^endif") ~= nil
  end
  local function isIfdefExpr(line)
    return line:match("^ifdef") ~= nil
  end
  local function isElseExpr(line)
    return line:match("^else") ~= nil
  end
  local function isIfeqExpr(line)
    return line:match("^ifeq") ~= nil
  end


  local lines = {}
  local kvTable = {}

  local function getLine(index)
    while findFirstMakefileVarKey(lines[index]) do
      local key = findFirstMakefileVarKey(lines[index])
      if key == nil then break end

      local value = kvTable[key]
      if not value then
        if MAKEFILE_PARSER_DEBUG_FLAG then print("[DEBUG]key is not defined:" .. key) end
        value = ""
      end
      lines[index] = replaceFirstMakefileKey(lines[index], key, value)
    end

    return lines[index]
  end

  local function parseIfdefExpr(current_kvtable, if_expr_index) end
  local function parseIfeqExpr(current_kvtable, if_expr_index)
    -- the %(KEY) could be a empty string
    local isEqExpr1, isEqExpr2 = getLine(if_expr_index):match("ifeq%s*%(([^,]*),([^,]*)%)")
    isEqExpr1 = simplicate_str(isEqExpr1)
    isEqExpr2 = simplicate_str(isEqExpr2)

    local isEq = isEqExpr1 == isEqExpr2


    if isEq then
      local i = if_expr_index + 1
      while i <= #lines do
        if isIfdefExpr(getLine(i)) then
          i = parseIfdefExpr(current_kvtable, i)
        elseif isIfeqExpr(getLine(i)) then
          i = parseIfeqExpr(current_kvtable, i)
        end

        if isEndifExpr(getLine(i)) then
          break
        end
        if isElseExpr(getLine(i)) then
          break
        end
        if isKVpattern(getLine(i)) then
          parseKVpattern(current_kvtable, getLine(i))
        end
        i = i + 1
      end

      return i
    else
      -- find the 'else' expr & add all new key-value into the current_kvtable which is after 'else' appears
      local i = if_expr_index + 1

      -- find next appear 'else' expr
      while i <= #lines do
        local ifStack = 0
        if isIfdefExpr(getLine(i)) then ifStack = ifStack + 1 end
        if isIfeqExpr(getLine(i)) then ifStack = ifStack + 1 end

        if ifStack == 0 and isElseExpr(getLine(i)) then
          break
        end
        i = i + 1
      end

      -- add all new key-value into the current_kvtable which is after next 'else' appears
      while i <= #lines do
        if isIfdefExpr(getLine(i)) then
          i = parseIfdefExpr(current_kvtable, i)
        elseif isIfeqExpr(getLine(i)) then
          i = parseIfeqExpr(current_kvtable, i)
        end

        if isEndifExpr(getLine(i)) then
          break
        end
        if isKVpattern(getLine(i)) then
          local key, value = parseKVpattern(current_kvtable, getLine(i))
        end
        i = i + 1
      end

      return i
    end
  end

  -- parse the ifdef DEF {muti-NEW_DEFS} else {else-NEW_DEFS} endif expr, return a table
  local function parseIfdefExpr(current_kvtable, if_expr_index)
    local ifdefExprMatchedKey = getLine(if_expr_index):match("^ifdef%s+(.+)")
    local isdefinedkey = current_kvtable[ifdefExprMatchedKey] ~= nil

    if isdefinedkey then
      -- add all new key-value into the current_kvtable which is befor next 'else' appear
      local i = if_expr_index + 1
      while i <= #lines do
        if isIfdefExpr(getLine(i)) then
          i = parseIfdefExpr(current_kvtable, i)
        elseif isIfeqExpr(getLine(i)) then
          i = parseIfeqExpr(current_kvtable, i)
        end

        if isEndifExpr(getLine(i)) then
          break
        end
        if isElseExpr(getLine(i)) then
          break
        end
        if isKVpattern(getLine(i)) then
          parseKVpattern(current_kvtable, getLine(i))
        end
        i = i + 1
      end

      return i
    else
      -- find the 'else' expr & add all new key-value into the current_kvtable which is after 'else' appears
      local i = if_expr_index + 1

      -- find next appear 'else' expr
      while i <= #lines do
        local ifStack = 0
        if isIfdefExpr(getLine(i)) then ifStack = ifStack + 1 end
        if isIfeqExpr(getLine(i)) then ifStack = ifStack + 1 end

        if ifStack == 0 and isElseExpr(getLine(i)) then
          break
        end
        i = i + 1
      end
      -- add all new key-value into the current_kvtable which is after next 'else' appears
      while i <= #lines do
        if isIfdefExpr(getLine(i)) then
          i = parseIfdefExpr(current_kvtable, i)
        elseif isIfeqExpr(getLine(i)) then
          i = parseIfeqExpr(current_kvtable, i)
        end

        if isEndifExpr(getLine(i)) then
          break
        end
        if isKVpattern(getLine(i)) then
          local key, value = parseKVpattern(current_kvtable, getLine(i))
        end
        i = i + 1
      end

      return i
    end
  end

  local makefile = io.open(makefile_locate, "r")
  if not makefile then
    if MAKEFILE_PARSER_DEBUG_FLAG then print("Makefile not found") end
    return {}
  end
  local makefile_content = makefile:read("*a")
  makefile:close()

  -- remove the line which is start with '#'
  makefile_content = makefile_content:gsub("#[^\n]*", "")
  -- replace the line which is end with '\' to the next line
  makefile_content = makefile_content:gsub("\\\n", "")
  -- simplicate the makefile content : remove multiple spaces
  makefile_content = makefile_content:gsub(" +", " "):gsub("\t+", " "):gsub("\n+", "\n")

  -- truncate the makefile content which is after the first 'all:' line
  makefile_content = makefile_content:match("^(.*)(.-all:.-)\n")


  for line in makefile_content:gmatch("[^\n]+") do
    if line:match("^%s+$") then
      goto continue
    end
    table.insert(lines, line)
    ::continue::
  end

  -- 获取Makefile文件所在的目录
  local makefile_dir = makefile_locate:match("(.+)/[^/]*$")
  if makefile_dir == nil then
    makefile_dir = "./"
  else
    makefile_dir = makefile_dir .. "/"
  end
  -- 向所有源码文件前添加当前目录的路径
  local function addDirPath(matchedLine, matchedPattern, dirPath)
    local newLine, lineArgs = matchedLine:match("^(.-%s*=%s-)(.+)")
    -- split the lineArgs by space
    for elem in lineArgs:gmatch("[^%s]+") do
      if matchedPattern == nil then
        newLine = newLine .. " " .. dirPath .. elem
      else
        newLine = newLine .. " " .. elem:gsub(matchedPattern, dirPath)
      end
    end
    return newLine
  end
  local function startWith(str, substr)
    return str:match("^" .. substr) ~= nil
  end

  for i, line in pairs(lines) do
    -- 修改ASM_SOURCES C_SOURCES AS_INCLUDES C_INCLUDES LDSCRIPT LIBDIR;
    if startWith(line, "ASM_SOURCES") then
      line = addDirPath(line, nil, makefile_dir)
    end
    if startWith(line, "C_SOURCES") then
      line = addDirPath(line, nil, makefile_dir)
    end
    if startWith(line, "AS_INCLUDES") then
      line = addDirPath(line, "-I", "-I" .. makefile_dir)
    end
    if startWith(line, "C_INCLUDES") then
      line = addDirPath(line, "-I", "-I" .. makefile_dir)
    end
    if startWith(line, "LDSCRIPT") then
      line = addDirPath(line, nil, makefile_dir)
    end
    if startWith(line, "LIBDIR") then
      line = addDirPath(line, "-L", "-L" .. makefile_dir)
    end

    lines[i] = line
  end


  local i = 1
  while i <= #lines do
    local line = getLine(i)

    if isKVpattern(line) then
      parseKVpattern(kvTable, line)
    elseif isIfdefExpr(line) then
      if MAKEFILE_PARSER_DEBUG_FLAG then print("line is ifdef expr:" .. line) end
      i = parseIfdefExpr(kvTable, i)
    elseif isIfeqExpr(line) then
      if MAKEFILE_PARSER_DEBUG_FLAG then print("line is ifeq expr:" .. line) end
      i = parseIfeqExpr(kvTable, i)
    else
      print("Makefile Parse Error: line unknown pattern:" .. line);
    end

    i = i + 1
  end

  if MAKEFILE_PARSER_DEBUG_FLAG then
    print("kvTable is:")
    for k, v in pairs(kvTable) do
      print("\t" .. k .. "\t\t:\t" .. v)
    end
  end


  -- 编译参数后处理


  -- 移除CFLAGS中的 -MF"$(@:%.o=%.d)"
  kvTable["CFLAGS"] = kvTable["CFLAGS"]:gsub("%s%-MF\"%$%(@:%%%.o=%%%.d%)\"", "")
  -- 移除CFLAGS中的 -Wl,-Map=$(BUILD_DIR)/$(TARGET).map"
  kvTable["LDFLAGS"] = kvTable["LDFLAGS"]:gsub(
    "%s%-Wl,%-Map=" .. kvTable["BUILD_DIR"] .. "/" .. kvTable["TARGET"] .. ".map,--cref", "")
  -- 移除CFLAGS 和 ASFLAGS 中和xmake中重复定义的参数 -g -gdwarf-2 -Og/-O0
  if kvTable["CFLAGS"]:match("%s%-g%s") then
    kvTable["CFLAGS"] = kvTable["CFLAGS"]:gsub("%s%-g%s", " ")
  end
  if kvTable["CFLAGS"]:match("%s%-gdwarf%-2%s") then
    kvTable["CFLAGS"] = kvTable["CFLAGS"]:gsub("%s%-gdwarf%-2%s", " ")
  end
  if kvTable["CFLAGS"]:match("%s%-Og%s") then
    kvTable["CFLAGS"] = kvTable["CFLAGS"]:gsub("%s%-Og%s", " ")
  end
  if kvTable["CFLAGS"]:match("%s%-O0%s") then
    kvTable["CFLAGS"] = kvTable["CFLAGS"]:gsub("%s%-O0%s", " ")
  end

  if kvTable["ASFLAGS"]:match("%s%-g%s") then
    kvTable["ASFLAGS"] = kvTable["ASFLAGS"]:gsub("%s%-g%s", " ")
  end
  if kvTable["ASFLAGS"]:match("%s%-gdwarf%-2%s") then
    kvTable["ASFLAGS"] = kvTable["ASFLAGS"]:gsub("%s%-gdwarf%-2%s", " ")
  end
  if kvTable["ASFLAGS"]:match("%s%-Og%s") then
    kvTable["ASFLAGS"] = kvTable["ASFLAGS"]:gsub("%s%-Og%s", " ")
  end
  if kvTable["ASFLAGS"]:match("%s%-O0%s") then
    kvTable["ASFLAGS"] = kvTable["ASFLAGS"]:gsub("%s%-O0%s", " ")
  end
    

  -- 添加链接器
  kvTable["LD"] = kvTable["CC"]
  -- 添加CFLAGS
  kvTable["CFLAGS"] = kvTable["CFLAGS"] .. " -Wa,-a,-ad"


  return kvTable
end
