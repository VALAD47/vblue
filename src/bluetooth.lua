local ldbus = require 'ldbus'
local inspect = require 'inspect'
local task = require 'task'
local signal = require 'signal'
local lgi = require 'lgi'
local color = require 'color'
local Gtk = lgi.Gtk
local GLib = lgi.GLib
 
--[[

	type Device: 		bluez_Device1
	type DeviceTree: 	{ dev: Device, list_box_row: ListBoxRow }
	type dev_PATH: 		bluez_Device1_path

--]]

local sys_dbus = ldbus.bus.get("system")

local bluetooth = {}
	bluetooth.LIST = nil

--		[ListBoxRow]: dev_PATH
local list_devices = {}

--	[DeviceTree]
local devices = setmetatable({}, {
	-- 					   t: table
	--						  key: dev_PATH
	--							   value: DeviceTree
	__newindex = function (t, key, value)
		local list_box_row = Gtk.ListBoxRow {}
		local label = Gtk.Label { label = value.dev.Alias or value.dev.Address }
		list_box_row:set_child(label)
		bluetooth.LIST:append(list_box_row)

		--			 [ListBoxRow]:   dev_PATH
		list_devices[list_box_row] = key


		--	[DeviceTree]:	  ListBoxRow
		value.list_box_row = list_box_row

		--	   t: table
		--		  key: dev_PATH
		--			   value: DeviceTree
		rawset(t, key, value)
	end,
	__index = {
		update = signal.new()
	}
})

-- 								path: dev_PATH
devices.update:connect(function(path)
	if devices[path].dev.Connected then
		bluetooth.CONNECTED_LABEL:set_label("Connected: " .. devices[path].dev.Alias)
		return
	end
	devices[path].list_box_row:get_child():set_use_underline(false)
end)

local function string_starts(String, Start)
	return string.sub(String, 1, string.len(Start)) == Start
end

local function unwrap(iter)
	local first = true
	local results = {}
	while first or iter:next() do
		first = false
		if iter:get_arg_type() == "a" or iter:get_arg_type() == "r" then 	-- array or struct
			local ret = unwrap(iter:recurse())
			table.insert(results, ret)
		elseif iter:get_arg_type() == "e" then 								-- dict_entry
			local ret = unwrap(iter:recurse())
			results[ret[1]] = ret[2]
		elseif iter:get_arg_type() == "v" then 								-- variant
			local ret = unwrap(iter:recurse())
			table.insert(results, ret[1])
		else 																-- basic type
			local ret = iter:get_basic()
			table.insert(results, ret)
		end
	end
	return results
end

local function call_dbus(destination, path, iface, method)
	local msg = ldbus.message.new_method_call(destination, path, iface, method)
	local iter = ldbus.message.iter.new()
	msg:iter_init_append(iter)

	local response = sys_dbus:send_with_reply_and_block(msg)

	if not response:iter_init(iter) then
		return nil
	end

	return unwrap(iter)
end

function bluetooth.discover_devices()
	task.spawn(function()
		local msg =
			ldbus.message.new_method_call("org.bluez", "/org/bluez/hci0", "org.bluez.Adapter1", "StartDiscovery")
		sys_dbus:send(msg)

		while task.wait(1) do
			local devs = call_dbus("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")
			bluetooth.CONNECTED_LABEL:set_label("Connected: [nil]")

			if not devs then
				goto continue
			end

			for i, v in pairs(devices) do
				if not devs[1][i] then
					bluetooth.LIST:remove(devices[i].list_box_row)
					devices[i] = nil
				end
			end

			for i, v in pairs(devs[1]) do
				if string_starts(i, "/org/bluez/hci0/") and v["org.bluez.Device1"] ~= nil then
					if not devices[i] then 
						devices[i] = { dev = v["org.bluez.Device1"] }
					else
						devices[i].dev = v["org.bluez.Device1"]
						devices.update:fire(i)
					end
				end
			end
		    ::continue::
		end
	end)
end

function bluetooth.connect(dev)
	if not dev then print("No selected") return end
	local msg = call_dbus("org.bluez", list_devices[dev], "org.bluez.Device1", "Connect")
	print(inspect(msg))
end

function bluetooth.disconnect(dev) 
	if not dev then print("No selected") return end
	local msg = call_dbus("org.bluez", list_devices[dev], "org.bluez.Device1", "Disconnect")
	print(inspect(msg))
end

return bluetooth
