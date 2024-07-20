local ldbus = require 'ldbus'
local task = require 'task'
local signal = require 'signal'
local lgi = require 'lgi'
local Gtk = lgi.Gtk
local GLib = lgi.GLib

signal.MULTI_THREAD = true

--[[

	type Device: 		bluez_Device1
	type DeviceTree: 	{...{ dev: Device, list_box_row: ListBoxRow }}
	type dev_PATH: 		bluez_Device1_path

--]]

-- System DBus, on which we will send requests
local sys_dbus = ldbus.bus.get("system")

-- Table that contains all functions and will be returned at end
local bluetooth = {}
	-- List that we will using to show all devices
	bluetooth.LIST = nil

--[[
	Table with devices on list

	[ListBoxRow]: dev_PATH
]]
local list_devices = {}

--[[
	Table with all discovered devices

	{
		dev: Device,
		list_box_row: ListBoxRow,
	}
]]
local devices = setmetatable({}, {
	--[[
		We will catch all new devices, and show them on the list

		t: table
		key: dev_PATH
		value: { dev: Device }
	]]
	__newindex = function (t, key, value)
		-- List row, that is used to show and indetify device
		local list_box_row = Gtk.ListBoxRow {}

		-- Label with name of device, if it exist.
		-- If not, we using device MAC address
		local label = Gtk.Label { label = value.dev.Alias or value.dev.Address }
		list_box_row:set_child(label)

		-- Sending our list row to main list
		bluetooth.LIST:append(list_box_row)

		-- Adding our new list row to list of showen devices.
		--
		-- Key of value is list row we created
		-- Value is dev_PATH
		list_devices[list_box_row] = key


		-- Adding list row to table that represents device
		value.list_box_row = list_box_row


		-- Adding new device to devices table
		--
		-- key: dev_PATH
		-- value: {dev: Device, list_box_row: ListBoxRow}
		rawset(t, key, value)
	end,
	__index = {
		update = signal.new()
	}
})

-- Event that will be fired every time device being updated
devices.update:connect(function(path)
	-- If updated device is connected, we showing that he is connected
	if devices[path].dev.Connected then
		bluetooth.CONNECTED_LABEL:set_label("Connected: " .. devices[path].dev.Alias)
	end
end)

-- Returning true, if `String` is started with `Start`
local function string_starts(String, Start)
	return string.sub(String, 1, string.len(Start)) == Start
end

-- Translating DBus response into lua table
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

--[[
	Calling DBus

	destination: service to which we calling
	path: path to device which we calling method for
	iface: interface that we using, like `org.bluez.Device1`
	method: method which we calling
]]
local function call_dbus(destination, path, iface, method)
	local msg = ldbus.message.new_method_call(destination, path, iface, method)
	local iter = ldbus.message.iter.new()
	msg:iter_init_append(iter)

	local response = sys_dbus:send_with_reply_and_block(msg)

	if not response or not response:iter_init(iter) then
		return nil
	end

	return unwrap(iter)
end

-- Loop of discovering devices
function bluetooth.discover_devices()
	-- We ofc run it in multi-thread, we do not want to suspend program
	task.spawn(function()
		-- Saying to bluez to start discover device on first adapter
		local msg = ldbus.message.new_method_call("org.bluez", "/org/bluez/hci0", "org.bluez.Adapter1", "StartDiscovery")
		sys_dbus:send(msg)

		-- We doing this every second
		while task.wait(1) do
			-- Getting devices that bluez manages
			local devs = call_dbus("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")

			-- Always resetting connected lable to nil, we anyways setting this on every cycle if have connect, so don't feel difference
			bluetooth.CONNECTED_LABEL:set_label("Connected: [nil]")

			-- If we don't have any devices, why we should parse them?
			if not devs then
				goto continue
			end

			-- Searching for removed devices, and removing them from all tables
			for i, v in pairs(devices) do
				if not devs[1][i] then
					bluetooth.LIST:remove(devices[i].list_box_row)
					devices[i] = nil
				end
			end

			-- Searching for devices
			for i, v in pairs(devs[1]) do
				if string_starts(i, "/org/bluez/hci0/") and v["org.bluez.Device1"] ~= nil then
					-- If it's first time discovered, we should send completely new table with `dev` set to device. This will alse target metamethod
					if not devices[i] then
						devices[i] = { dev = v["org.bluez.Device1"] }
					else
					-- If it's not first time discovered, we only updating `dev` part, because we don't want to clear `list_box_row`
						devices[i].dev = v["org.bluez.Device1"]
						devices.update:fire(i)
					end
				end
			end
		    ::continue::
		end
	end)
end

-- Connecting to device. Using ListBoxRow as index of device
function bluetooth.connect(dev)
	if not dev then print("No selected") return end
	local msg = ldbus.message.new_method_call("org.bluez", list_devices[dev], "org.bluez.Device1", "Connect")
	sys_dbus:send(msg)
end

-- Disconnecting to device. Using ListBoxRow as index of device
function bluetooth.disconnect(dev)
	if not dev then print("No selected") return end
	local msg = ldbus.message.new_method_call("org.bluez", list_devices[dev], "org.bluez.Device1", "Disconnect")
	sys_dbus:send(msg)
end

return bluetooth
