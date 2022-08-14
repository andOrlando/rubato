local easing = require(RUBATO_DIR.."easing")
--[[
manager.timed.defaults.rate = 60 --sets default rate to 60
manager.timed.override.rate = 30 --sets all rates to 30
manager.timed.override.clear() --resets timeds to their initial values
manager.timed.override.forall(function(timed) print(timed) end) --prints all timeds
if you only want to do something to specific timeds you can tag them beforehand
with some attribute or something and then check for that attribute when calling
forall
]]

local function make_props_immutable(table)
	setmetatable(table, {
		__index = function(self, key)
			if self._props[key] then return self._props[key]
			else return rawget(self, key) end
		end,
		__newindex = function(self, key, value)
			if self._props[key] then return
			else self._props[key] = value end
		end,
	})
end


local function manager()
	local obj = {_props = {}}
	make_props_immutable(obj)

	obj._props.timeds = {}

	obj._props.timed = {_props = {}}
	obj._props.timed._props.defaults = {
		duration = 1,
		pos = 0,
		prop_intro = false,
		intro = 0.2,
		easing = easing.linear,
		awestore_compat = false,
		log = function() end,
		override_simulate = false,
		override_dt = false,
		rate = 60,
	}
	make_props_immutable(obj.timed)
	obj._props.timed._props.override = {_props = {
		clear = function() for _, timed in pairs(obj.timeds) do timed:reset_values() end end,
		forall = function(func) for _, timed in pairs(obj.timeds) do func(timed) end end,
	}}

	setmetatable(obj.timed.override, {
		__index = function(self, key) return self._props[key] end,
		__newindex = function(self, key, value)
			for _, timed in pairs(obj.timeds) do timed[key] = value end
			self._props[key] = value
		end
	})

	return obj
end

return RUBATO_MANAGER or manager()
