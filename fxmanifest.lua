fx_version "cerulean"
game "gta5"
version "v1.0.5"

ui_page "nui/index.html"

files {
	"nui/index.html",
	"nui/assets/**/*.*",
}

shared_scripts {
	"@ox_lib/init.lua",
	"config.lua",
	"locales/locale.lua",
    "locales/translations/*.lua",
	"bridge/**/shared.lua",
	"modules/**/shared.lua",
    "core/shared.lua"
}

client_scripts {
	"bridge/**/client.lua",
	"modules/**/client.lua",
    "core/client.lua"
}

server_scripts {
	"bridge/**/server.lua",
	"modules/**/server.lua",
}

lua54 'yes'
