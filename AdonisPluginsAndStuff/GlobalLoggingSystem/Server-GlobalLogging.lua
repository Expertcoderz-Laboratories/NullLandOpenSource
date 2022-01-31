--[[
	Description: Framework to empower surveillance.
	Author: Expertcoderz
	Release Date: 2022-01-28
--]]

server, service = nil, nil

local DATASTORE_NAME = "NullLand/GlobalLogs"
local DATASTORE_KEY = "Logs"

--// "exporting" = writing the current server's logs and info to the datastore
local EXPORT_LOG_IN_STUDIO = false
local EXPORT_LOG_INTERVAL = 70
local EXPORT_LOG_ON_CLOSE = true

--// measured in no. of characters when the data is serialized
local LOG_SIZE_BEFORE_WARN = 3_000_000
local CRITICAL_LOG_SIZE = 3_500_000
local DATASTORE_SIZE_LIMIT = 4_000_000

local GLOBAL_LOGS_PERMS = {
	--// AdminLevels or rank names eg. "HeadAdmins"
	List = 900,
	Clear = 900,

	Open = 900,
	Delete = 900,

	Export = 900,

	ReceiveOverloadWarning = 900,
}

local LOGS_TO_INCLUDE = {
	--// Names of log tables under server.Logs
	"Chats", "Commands", "Exploit", "Script", --"Interaction"
}

local function FormatNumber(num: number): string
	if not num then return "NaN" end
	if num >= 1e150 then return "Inf" end
	num = tostring(num):reverse()
	local new = ""
	local counter = 1
	for i = 1, #num do
		if counter > 3 then
			new ..= ","
			counter = 1
		end
		new ..= num:sub(i, i)
		counter += 1
	end
	return new:reverse()
end

return function()
	xpcall(function()

		local GlobalLogStore: DataStore = service.DataStoreService:GetDataStore(DATASTORE_NAME)
		server.Variables.GlobalLogStore = GlobalLogStore

		local _serverId = string.format("%x", os.time())
		workspace:SetAttribute("_ServerId", _serverId)

		local _uniqueJoins: number, _firstJoin: string = {}, nil

		local _serverCountry = select(2, xpcall(function()
			return service.HttpService:JSONDecode(service.HttpService:GetAsync("http://ip-api.com/json")).country
		end, function(err)
			warn("Error fetching server location info;", err)
			return "[Error]"
		end))

		server.Functions.ExportGlobalLog = function(manual: boolean?): boolean?
			if EXPORT_LOG_IN_STUDIO or manual or not service.RunService:IsStudio() then
				return xpcall(function()
					GlobalLogStore:UpdateAsync(DATASTORE_KEY, function(currentLogs)
						if not currentLogs then
							warn("Initial global logging datastore setup")
							currentLogs = {}
						end
						local currentSize = #service.HttpService:JSONEncode(currentLogs)
						if currentSize > CRITICAL_LOG_SIZE then
							warn("GLOBAL EXPORTED LOG STORE CRITICALLY APPROACHING", DATASTORE_SIZE_LIMIT, "CHARACTER LIMIT:", currentSize)
							warn("CLEARING LOGS STARTING FROM EARLIEST UNTIL TOTAL SIZE <=", CRITICAL_LOG_SIZE, "CHARS")
							local ids = {}
							for id in pairs(currentLogs) do table.insert(ids, tonumber(id, 16)) end
							table.sort(ids)
							repeat
								currentLogs[ids[1]] = nil
								table.remove(ids, ids[1])
							until #service.HttpService:JSONEncode(currentLogs) <= CRITICAL_LOG_SIZE
						end
						local dataToExport = {
							_JobId = if game.JobId then tostring(game.JobId) else "[Unknown JobId]";
							_ServerType = if game.PrivateServerOwnerId ~= 0 then "Private"
								elseif game.PrivateServerId ~= "" then "Reserved"
								elseif service.RunService:IsStudio() then "Studio"
								else "Standard";
							_PrivateServerId = if game.PrivateServerId ~= "" then game.PrivateServerId else nil;
							_PrivateServerOwnerId = if game.PrivateServerOwnerId ~= 0 then game.PrivateServerOwnerId else nil;
							_StartTime = math.round(os.time() - time());
							_ServerAge = math.round(time() / 60);
							_UniqueJoins = #_uniqueJoins;
							_FirstJoin = _firstJoin or "N/A";
							_ServerCountry = _serverCountry;
						}
						for _, logType in pairs(LOGS_TO_INCLUDE) do
							dataToExport[logType] = server.Logs[logType]
						end
						currentLogs[_serverId] = service.HttpService:JSONEncode(dataToExport)
						return currentLogs
					end)
					print("Exported global log for this server", _serverId)
				end, function(err)
					warn("Unable to export to global log datastore:", err)
				end)
			end
			return nil
		end

		task.defer(function()
			if not EXPORT_LOG_INTERVAL or EXPORT_LOG_INTERVAL >= math.huge then return end
			while task.wait(EXPORT_LOG_INTERVAL) do
				server.Functions.ExportGlobalLog()
			end
		end)
		if EXPORT_LOG_ON_CLOSE then game:BindToClose(server.Functions.ExportGlobalLog) end

		service.Events.PlayerAdded:Connect(function(plr: Player)
			if not table.find(_uniqueJoins, plr.UserId) then
				table.insert(_uniqueJoins, plr.UserId)
			end
			if not _firstJoin then _firstJoin = "@"..plr.Name end
			task.defer(function()
				task.wait(3)
				if
					server.Admin.CheckComLevel(server.Admin.GetLevel(plr), GLOBAL_LOGS_PERMS.ReceiveOverloadWarning)
					and select(2, xpcall(function()
						local chars = 0
						for id: string, json: string in pairs(GlobalLogStore:GetAsync(DATASTORE_KEY) or {}) do
							chars += #json
						end
						return chars >= LOG_SIZE_BEFORE_WARN
					end, function(err) warn("Unable to get exported logs store size:", err) return false end))
				then
					server.Remote.MakeGui(plr, "Notification", {
						Title = "Warning!";
						Icon = server.MatIcons.Warning;
						Text = "Global exported log store reaching datastore value limit!";
						Time = 25;
					})
				end
			end)
		end)

		server.Commands.GetServerId = {
			Prefix = server.Settings.PlayerPrefix;
			Commands = {"serverid", "getserverid", "viewserverid"};
			Args = {};
			Description = "Tells you the current server's ID";
			AdminLevel = 0;
			Function = function(plr: Player, args: {string})
				server.Functions.Hint(string.format("The ID of this server is: %s", _serverId), {plr})
			end
		}

		server.Commands.ListExportedLogs = {
			Prefix = server.Settings.Prefix;
			Commands = {"exportedlogs", "globallogs", "listexportedlogs", "getexportedlogs"};
			Args = {};
			Description = "Opens a list of exported global logs";
			AdminLevel = GLOBAL_LOGS_PERMS.List;
			Function = function(plr: Player, args: {string})
				local prefix = server.Settings.Prefix
				local split = server.Settings.SplitKey

				server.Functions.Hint("Loading exported logs...", {plr})

				local globalLogs = select(2, xpcall(function()
					return GlobalLogStore:GetAsync(DATASTORE_KEY) or {}
				end, function(err)
					warn("Error listing global exported logs:", err)
					return nil
				end))
				assert(globalLogs, "Error occurred listing global exported logs")

				local num = 0
				local children = {
					server.Core.Bytecode([[Object:ResizeCanvas(false, true, false, false, 5, 5)]]);
					{
						Class = "UIListLayout";
						SortOrder = Enum.SortOrder.LayoutOrder;
						HorizontalAlignment = Enum.HorizontalAlignment.Center;
						VerticalAlignment = Enum.VerticalAlignment.Top;
					}
				}

				for id: string, json: string in pairs(globalLogs) do
					local decoded = service.HttpService:JSONDecode(json)
					table.insert(children, {
						Class = "TextLabel";
						LayoutOrder = -tonumber(id, 16);
						Size = UDim2.new(1, -10, 0, 30);
						BackgroundTransparency = 1;
						TextXAlignment = "Left";
						Text = "  ["..(server.Remote.Get(plr, "LocallyFormattedTime", decoded._StartTime, true) or "Unknown").."] "..id;
						ToolTip = string.format("#: %s | Type: %s | First Join: %s", FormatNumber(#json), tostring(decoded._ServerType), tostring(decoded._FirstJoin));
						ZIndex = 2;
						Children = {
							{
								Class = "TextButton";
								Size = UDim2.new(0, 80, 1, -4);
								Position = UDim2.new(1, -82, 0, 2);
								Text = "Open";
								ToolTip = "#: "..#json;
								ZIndex = 3;
								OnClick = server.Core.Bytecode([[
								if not Object.Parent.ImageButton.Active or not Object.Active then return end
								Object.Active = false
								client.Remote.Send("ProcessCommand", "]]..prefix..[[viewexportedlog]]..split..id..[[")
								wait(1)
								Object.Active = true
								]]);
							},
							{
								Class = "ImageButton";
								Size = UDim2.new(0, 26, 0, 26);
								Position = UDim2.new(1, -110, 0, 2);
								Image = server.MatIcons.Delete;
								ZIndex = 3;
								OnClick = server.Core.Bytecode([[
								if not Object.Active then return end
								Object.Active = false
								client.Remote.Send("ProcessCommand", "]]..prefix..[[delexportedlog]]..split..id..[[")
								Object.Parent:TweenSize(UDim2.new(0, 0, 0, 30), "Out", "Quint", 0.4)
								task.wait(0.3)
								Object.Parent:Destroy()
								]]);
							},
						};
					})
					num += 1
				end

				local len = #service.HttpService:JSONEncode(globalLogs)
				server.Remote.MakeGui(plr, "Window", {
					Name = "ExportedLogs";
					Title = "Exported Logs ("..num..") [#: "..FormatNumber(len).."]";
					Icon = server.MatIcons.Description;
					Size  = {330, 250};
					MinSize = {300, 180};
					Content = children;
					Ready = true;
				})
			end
		}

		server.Commands.ViewExportedLog = {
			Prefix = server.Settings.Prefix;
			Commands = {"viewexportedlog", "openexportedlog", "viewgloballog", "opengloballog"};
			Args = {"server ID"};
			Description = "Opens a specific exported log";
			AdminLevel = GLOBAL_LOGS_PERMS.Open;
			Function = function(plr: Player, args: {string})
				assert(args[1], "Server ID not specified")
				server.Remote.MakeGui(plr, "GlobalLogViewer", {ServerId = args[1];})
			end
		}

		server.Remote.Returnables.ExportedLog = function(plr: Player, args)
			if server.Admin.CheckComLevel(server.Admin.GetLevel(plr), GLOBAL_LOGS_PERMS.Open) then
				return select(2, xpcall(function()
					local data = (GlobalLogStore:GetAsync(DATASTORE_KEY) or {})[args[1]]
					return if data then service.HttpService:JSONDecode(data) else nil
				end, function()
					return false
				end))
			end
			server.Remote.RemoveGui(plr, "GlobalLogViewer")
		end

		server.Commands.DeleteExportedLog = {
			Prefix = server.Settings.Prefix;
			Commands = {"delexportedlog", "deleteexportedlog", "delgloballog", "deletegloballog"};
			Args = {"server ID"};
			Description = "Removes a specific exported log from the datastore";
			AdminLevel = GLOBAL_LOGS_PERMS.Delete;
			Function = function(plr: Player, args: {string})
				assert(args[1], "Server ID not specified")
				local success, res = pcall(function()
					local existed = false
					GlobalLogStore:UpdateAsync(DATASTORE_KEY, function(currentLogs)
						if currentLogs and currentLogs[args[1]] then
							existed = true
							currentLogs[args[1]] = nil
						end
						return currentLogs
					end)
					return existed
				end)
				if success then
					server.Functions.Hint((if res then "Successfully deleted global log: " else "Global log not found: ")..args[1], {plr})
				else
					error("An error occurred whilst attempting to call RemoveAsync.")
				end
			end
		}

		server.Commands.ClearExportedLogs = {
			Prefix = server.Settings.Prefix;
			Commands = {"clearexportedlogs"};
			Args = {};
			Description = "Removes all exported logs from the datastore";
			AdminLevel = GLOBAL_LOGS_PERMS.Clear;
			Function = function(plr: Player, args: {string})
				if server.Remote.GetGui(plr, "YesNoPrompt", {Question = "Would you like to delete all exported global logs?"}) == "Yes" then
					if
						pcall(function()
							GlobalLogStore:RemoveAsync(DATASTORE_KEY)
						end)
					then
						server.Functions.Hint("Successfully cleared all global exported logs.", {plr})
					else
						error("Error occurred clearing global exported logs.")
					end
				end
			end
		}

		server.Commands.ExportGlobalLog = {
			Prefix = server.Settings.Prefix;
			Commands = {"exportgloballog", "exportgloballogs", "exportlogs", "exportlog"};
			Args = {};
			Description = "Manually export the global logs for this server";
			AdminLevel = GLOBAL_LOGS_PERMS.Export;
			Function = function(plr: Player, args: {string})
				if server.Functions.ExportGlobalLog(true) then
					server.Functions.Hint("Exported the global log for this server.", {plr})
				else
					error("Error exporting global log for this server.")
				end
			end
		}

	end, function(err)
		warn("[CRITICAL] Global logging plugin failed to load:", err)
	end)
end
