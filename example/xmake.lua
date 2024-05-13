add_rules("mode.debug", "mode.release")
set_allowedarchs("arm")
set_defaultarchs("arm")
set_allowedplats("cross")
set_defaultplat("cross")

-- add the cross toolchain from makefile
toolchain("auto_detected_from_makefile_toolchain")
  set_kind("standalone")
  set_description("Auto detected toolchain from Makefile")
  on_load(function (toolchain)

    local makefile_table = {}
    import("makefile_luaparser.parser")

    -- load the makefile
    makefile_table = parser("./mcu/Makefile")

    toolchain:set("toolset", "cc", makefile_table["CC"])
    toolchain:set("toolset", "ld", makefile_table["LD"])
    toolchain:set("toolset", "as", makefile_table["CC"])
    toolchain:set("toolset", "sh", makefile_table["CC"])
    toolchain:set("toolset", "ar", makefile_table["CC"])

    toolchain:add("asflags",makefile_table["ASFLAGS"])
    toolchain:add("cxflags",makefile_table["CFLAGS"])
    toolchain:add("ldflags",makefile_table["LDFLAGS"])

    -- for k, v in pairs(makefile_table) do
    -- print("xmake.parser " .. k .. "\t\t:\t" .. v)
    -- end

    toolchain:set("toolset", "cxx", "arm-none-eabi-g++")
    toolchain:add("cxxflags", makefile_table["CFLAGS"] .. " -std=c++23")

    print(toolchain:get("cxflags"))

    print("xmake.parser: toolchain loaded")
  end)

toolchain_end()

-- to compile the project, you need to configure as:
-- > xmake f
-- and then build the project as:
-- > xmake
-- > to flash the target, you can use:
-- > xmake r
-- > it will copy the target to ./target/target.elf and then flash the target using openocd.exe
target("demo-proj.elf", function (target) 
  set_toolchains("auto_detected_from_makefile_toolchain")
  set_kind("binary")
  add_files("App/Src/*.cpp")
  add_includedirs("App/Inc")
  set_default(true)

  -- set the optimize level, could be "none", "fastest", "faster", "fast", "smaller", "smallest"
  set_optimize("none")

  local makefile_table = {} 
  on_load(function (target)
    -- add source files & include directories from makefile
    import("makefile_luaparser.parser")
    makefile_table = parser("./mcu/Makefile")
    for file in makefile_table["C_INCLUDES"]:gmatch("[^%s]+") do
      target:add("cincludes", file)
    end
    for file in makefile_table["AS_INCLUDES"]:gmatch("[^%s]+") do
      target:add("includedirs", file)
    end
    for file in makefile_table["LIBDIR"]:gmatch("[^%s]+") do
      target:add("linkdirs", file)
    end

    for file in makefile_table["C_SOURCES"]:gmatch("[^%s]+") do
      target:add("files", file, {rule = "c"})
    end
    for file in makefile_table["ASM_SOURCES"]:gmatch("[^%s]+") do
      target:add("files", file, {rule = "asm"})
    end
  end);


  -- generate the hex;bin file
  after_build(function (target)
    os.exec(makefile_table["HEX"] .. " " .. target:targetfile() .. " " .. target:targetfile():match("(.*).elf") .. ".hex")
    os.exec(makefile_table["BIN"] .. " " .. target:targetfile() .. " " .. target:targetfile():match("(.*).elf") .. ".bin")
    os.exec(makefile_table["SZ"] .. " " .. target:targetfile())
  end)

  -- flash the target using os.exec command
  on_run(function (target)
    -- copy the target to ./target/target.elf
    os.cp(target:targetfile(), "./target/target.elf")
    -- os.cp(target:targetfile():match("(.*).bin"), "./target/target.bin")

    local command = "openocd -f openocd.cfg -c \"program " .. target:targetfile():match("(.*).elf") .. ".hex\" " .. "-c \"reset run\" -c \"exit\""
    print("flush the target: %s", target:targetfile() .. " with argument:\n\t" .. command)
    os.exec(command)
  end)

end)
target_end()
