local ldbus = require 'ldbus'
local task = require 'task'
local signal = require 'signal'
local lgi = require 'lgi'
local Gtk = lgi.Gtk
local GLib = lgi.GLib

signal.MULTI_THREAD = true
task.ESCAPE_ROW 	= 15

local color = function (s, n)
	return "\27[38;5;".. n%256 .."m"..tostring(s).."\27[0m"
end

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
bluetooth.DEBUG = false


local debug = {}
debug.INSPECT = nil

-- Printing human readable value
--
-- t: any
function debug.inspect(t, name)
	if not bluetooth.DEBUG then return end
	if not debug.INSPECT then
		debug.INSPECT = require('inspect')
	end

	print((color("[ %.3f ]", 235)):format(os.clock()), color("[ BLUETOOTH ]", 27), name, debug.INSPECT(t))
end

function debug.print(pos, ...)
	if bluetooth.DEBUG then
		print(("\27[%dH"..color("[ %.3f ]", 235)):format(pos+task.MAX_DEBUG_ROW ,os.clock()), color("[ BLUETOOTH ]", 27 ), ...)
	end
end

-- Send notification to system
local function notify(s)
	debug.print(5, "New notify with text ", s)
	os.execute(("notify-send -a vblue -c bluetooth \"%s\""):format(s))
end

--[[
	Table with devices on list

	[ListBoxRow]: dev_PATH
]]
local list_devices = {}

-- Saved value of device battery percentage
local battery = -1

--[[
	Table with all discovered devices

	[dev_PATH]: {
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
	__newindex = function(t, key, value)
		debug.print(0, "Discovered", value.dev.Address);
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
		if devices[path].battery and devices[path].battery.Percentage ~= battery then
			battery = devices[path].battery.Percentage
			debug.print(4, ("New battery percentage: %d"):format(battery))
			notify(("%s: %d%%"):format(devices[path].dev.Alias or devices[path].dev.Address, battery))
		end
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
		if iter:get_arg_type() == "a" then 		-- array
			local ret = unwrap(iter:recurse())
			table.insert(results, ret)
		elseif iter:get_arg_type() == "e" then 	-- dict_entry
			local ret = unwrap(iter:recurse())
			results[ret[1]] = ret[2]
		elseif iter:get_arg_type() == "v" then 	-- variant
			local ret = unwrap(iter:recurse())
			table.insert(results, ret[1])
		elseif iter:get_arg_type() == "r" then	-- struct
			local ret = unwrap(iter:recurse())
			table.insert(results, ret)
		else 									-- basic type
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
	...: {value, ldbus.types.*}
]]
local function call_dbus(destination, path, iface, method, ...)
	local msg = assert(ldbus.message.new_method_call(destination, path, iface, method), "Message NULL")
	local iter = ldbus.message.iter.new()
	msg:iter_init_append(iter)

	for i,v in pairs({...}) do
		if type(v) == "table" then
			assert(iter:append_basic(v[1], v[2]), "Out of memory.")
		else
			assert(iter:append_basic(v), "Out of memory.")
		end
	end

	local response = assert(sys_dbus:send_with_reply_and_block(msg))

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



			--debug.inspect(devs)

			-- Searching for devices
			for i, v in pairs(devs[1]) do
				if string_starts(i, "/org/bluez/hci0/") and v["org.bluez.Device1"] ~= nil then
					-- If it's first time discovered, we should send completely new table with `dev` set to device. This will alse target metamethod
					if not devices[i] then
						devices[i] = { dev = v["org.bluez.Device1"], battery = v["org.bluez.Battery1"] }
					else
						-- If it's not first time discovered, we only updating `dev` part, because we don't want to clear `list_box_row`
						devices[i].dev = v["org.bluez.Device1"]
						devices[i].battery = v["org.bluez.Battery1"]
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
	if not dev then
		print("No selected")
		return
	end
	debug.print(1, "Connecting", devices[list_devices[dev]].dev.Address);
	local msg = ldbus.message.new_method_call("org.bluez", list_devices[dev], "org.bluez.Device1", "Connect")
	sys_dbus:send(msg)
end

-- Disconnecting to device. Using ListBoxRow as index of device
function bluetooth.disconnect(dev)
	if not dev then
		print("No selected")
		return
	end
	debug.print(2, "Disconnecting", devices[list_devices[dev]].dev.Address);
	local msg = ldbus.message.new_method_call("org.bluez", list_devices[dev], "org.bluez.Device1", "Disconnect")
	sys_dbus:send(msg)
end

function bluetooth.remove(dev)
	if not dev then
		print("No selected")
		return
	end
	debug.print(3, "Removing", devices[list_devices[dev]].dev.Address);
	local msg = call_dbus("org.bluez", "/org/bluez/hci0", "org.bluez.Adapter1", "RemoveDevice", {list_devices[dev], ldbus.types.object_path})
end

return bluetooth
