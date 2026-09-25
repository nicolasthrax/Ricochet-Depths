--!strict
-- A small typed signal, so services and controllers talk without requiring each other.
-- Handlers run synchronously, in connection order, on the firing thread; a handler connected or
-- disconnected during a Fire takes effect from the next Fire.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Entry<T...> = {
	connection: Connection,
	handler: (T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local entries: { Entry<T...> } = {}

	local function connect(_self: Signal<T...>, handler: (T...) -> ()): Connection
		local connection: Connection
		local entry: Entry<T...>
		connection = {
			Connected = true,
			Disconnect = function(self: Connection)
				if not self.Connected then
					return
				end
				self.Connected = false
				local index = table.find(entries, entry)
				if index then
					table.remove(entries, index)
				end
			end,
		}
		entry = { connection = connection, handler = handler }
		table.insert(entries, entry)
		return connection
	end

	local signal: Signal<T...> = {
		Connect = connect,
		Once = function(self: Signal<T...>, handler: (T...) -> ()): Connection
			local connection: Connection
			connection = connect(self, function(...: T...)
				connection:Disconnect()
				handler(...)
			end)
			return connection
		end,
		Fire = function(_self: Signal<T...>, ...: T...)
			for _, entry in table.clone(entries) do
				if entry.connection.Connected then
					entry.handler(...)
				end
			end
		end,
		DisconnectAll = function(_self: Signal<T...>)
			for _, entry in table.clone(entries) do
				entry.connection:Disconnect()
			end
		end,
	}
	return signal
end

table.freeze(Signal)
return Signal
