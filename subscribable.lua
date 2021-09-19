-- Kidna copying awesotre's stores on a surface level for added compaatibility
local function subscribable(args)
	local obj = args or {}
	local subscribed = {}
	local subscribed_i = {}
	local s_counter = 0

	-- Subscrubes a function to the object so that it's called when `fire` is
	-- Calls subscribe_callback if it exists as well
	function obj:subscribe(func)
		subscribed[s_counter] = func
		subscribed_i[func] = s_counter
		s_counter = s_counter + 1

		if self.subscribe_callback then self.subscribe_callback(func) end
	end

	-- Unsubscribes a function and calls unsubscribe_callback if it exists
	function obj:unsubscribe(func)
		if not func then
			subscribed = {}
			s_counter = 0
		else
			subscribed[subscribed_i[func]] = nil
			subscribed_i[func] = nil
		end

		if self.unsubscribe_callback then self.unsubscribe_callback(func) end
	end

	function obj:fire(...) for _, func in pairs(subscribed) do func(...) end end

	return obj
end

return subscribable
