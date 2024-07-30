#!/bin/lua
local lgi = require 'lgi'
local a = require 'async'
local Gtk = lgi.require('Gtk', '4.0')
local bluetooth = require('vblue/bluetooth')
local GLib = lgi.GLib
local task = require 'task'


if arg[1] == "--debug" then
    task.DEBUG = true
    bluetooth.DEBUG = true
end


local function printf(s, ...)
    print(string.format(s, ...))
end

--Creating our application, to which we will bind window
local app = Gtk.Application {
    application_id = "com.valad47.bluetooth.lua"
}

--Function, that will be activated on app startup
function app:on_activate()
    -- Main window with all interface
    local window = Gtk.Window {
        application = app,
        title = "VALAD bluetooth",
        resizable = false,
        default_width = 800,
        default_height = 450,
    }
    
    --[[ BOXES ]]

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

    local box3 = Gtk.Box {
        orientation = Gtk.Orientation.HORISONTAL
    }

    --[[ SCROLL BOX ]]

    -- List, which will contain all devices
    local list = Gtk.ListBox {}

    -- Sending this list to bluetooth
    bluetooth.LIST = list

    local scroll_window = Gtk.ScrolledWindow {
        child = list
    }
    scroll_window:set_size_request(535, 350)

    --[[ BUTTONS ]]

    --Exit button
    local button1 = Gtk.Button {
        label = "X",
        margin_top = 4,
        margin_end = 4
    }
    button1:set_size_request(50, 50)

    function button1:on_clicked()
        window:close()
    end

    local button_connect = Gtk.Button {
        label = "Connect"
    }
    button_connect:set_size_request(200, 40)
    function button_connect:on_clicked()
        -- Sending currently selected box row to bluetooth connect function
        bluetooth.connect(list:get_selected_row())
    end

    local button_disconnect = Gtk.Button {
        label = "Disconnect",
        margin_top = 10
    }
    button_disconnect:set_size_request(200, 40)
    function button_disconnect:on_clicked()
        -- Sending currently selected box row to bluetooth disconnect function
        bluetooth.disconnect(list:get_selected_row())
    end

    --Label to show currently connected device
    local connected = Gtk.Label {
        label = "Connected: [nil]"
    }
    connected:set_size_request(746, 0)

    --Sending label to bluetooth
    bluetooth.CONNECTED_LABEL = connected

    --Moving created elements on window
    box1:append(scroll_window)
    box1:append(buttons_box)

    buttons_box:append(button_connect)
    buttons_box:append(button_disconnect)

    box3:append(connected)
    box3:append(button1)

    main_box:append(box3)
    main_box:append(box1)

    window:set_child(main_box)

    --Showing window to user
    window:present()

    --Starting bluetooth device discovery 
    bluetooth.discover_devices()

    --Creating loop for task
    GLib.timeout_add(1, 1, task.step)
end

-- Running application
app:run()