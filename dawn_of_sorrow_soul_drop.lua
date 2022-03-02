function enable_soul_hack()
	mainmemory.write_u32_le(0x00012D94, 0xE1A00000)
	mainmemory.write_u32_le(0x000C07E4, 0x00000000)
end

function disable_soul_hack()
	mainmemory.write_u32_le(0x00012D94, 0xE58C0004)
end

event.onconsoleclose(disable_soul_hack)
enable_soul_hack()