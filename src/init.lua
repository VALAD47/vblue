local lgi = require 'lgi'
local a = require 'async'
local Gtk = lgi.require('Gtk', '4.0')
local bluetooth = require 'bluetooth'
local GLib = lgi.GLib
local inspect = require 'inspect'
local task = require 'task'
 
--task.DEBUG = true

local function printf(s, ...)
    print(string.format(s, ...))
end


local list = Gtk.ListBox {}

bluetooth.LIST = list

local app = Gtk.Application {
    application_id = "com.valad47.bluetooth.lua"
}
function app:on_activate()
    local window = Gtk.Window {
        application = app,
        title = "VALAD bluetooth",
        resizable = false,
        default_width = 800,
        default_height = 450,
    }

    local button1 = Gtk.Button {
        label = "X",
        margin_top = 4,
        margin_end = 4
    }
    button1:set_size_request(50, 50)

    function button1:on_clicked()
        window:close()
    end

    local main_box = Gtk.Box {
        orientation = Gtk.Orientation.VERTICAL
    }

    local box1 = Gtk.Box {
        orientation = Gtk.Orientation.HORISONTAL,
        margin_top = 25,
        margin_start = 25,
        margin_end = 25,
        margin_bottom = 25,
    }

    local buttons_box = Gtk.Box {
        orientation = Gtk.Orientation.VERTICAL,
        margin_start = 15,
    }

    local scroll_window = Gtk.ScrolledWindow {
        child = list
    }
    scroll_window:set_size_request(535, 350)

    local button_connect = Gtk.Button {
        label = "Connect"
    }
    button_connect:set_size_request(200, 40)
    function button_connect:on_clicked()
        bluetooth.connect
        
        
        (list:get_selected_row())
    end

    local button_disconnect = Gtk.Button {
        label = "Disconnect",
        margin_top = 10
    }
    button_disconnect:set_size_request(200, 40)
    function button_disconnect:on_clicked()
        bluetooth.disconnect(list:get_selected_row())
    end

    local box3 = Gtk.Box {
        orientation = Gtk.Orientation.HORISONTAL
    }

    local connected = Gtk.Label {
        label = "Connected: [nil]"
    }
    connected:set_size_request(746, 0)

    bluetooth.CONNECTED_LABEL = connected

    box1:append(scroll_window)
    box1:append(buttons_box)

    buttons_box:append(button_connect)
    buttons_box:append(button_disconnect)

    box3:append(connected)
    box3:append(button1)

    main_box:append(box3)
    main_box:append(box1)

    window:set_child(main_box)

    window:present()

    bluetooth.discover_devices()
    GLib.timeout_add(1, 1, task.step)
end

app:run()