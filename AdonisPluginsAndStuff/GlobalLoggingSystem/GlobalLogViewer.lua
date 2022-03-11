client, service = nil, nil

return function(data)
	local serverId = data.ServerId
	local fetch, logs = nil, nil

	local window = client.UI.Make("Window", {
		Name  = "GlobalLogViewer";
		Title = "Global Log Viewer ("..serverId..")";
		Icon = client.MatIcons.Description;
		Size  = {500, 280};
		MinSize = {400, 150};
		OnRefresh = function()
			fetch()
		end
	})

	local placeholder = window:Add("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5);
		Position = UDim2.fromScale(0.5, 0.5);
		BackgroundTransparency = 1;
		Text = "Loading...";
	})

	function fetch()
		local res = client.Remote.Get("ExportedLog", serverId)
		if res == nil then
			task.defer(client.UI.Make, "Output", {Message = "Log does not exist/invalid server ID.";})
			window:Close()
			return
		elseif not res then
			client.UI.Make("Output", {Message = "Error attempting to fetch log.";})
			return
		end
		logs = res

		window:ClearAllChildren()
		local tabFrame = window:Add("TabFrame", {
			Size = UDim2.new(1, -10, 1, -10);
			Position = UDim2.new(0, 5, 0, 5);
		})

		do
			local infoTab = tabFrame:NewTab("Info", {Text = "Info";})
			local i, currentPos = 0, 0
			for _, v in ipairs({
				{"Log Size (~#chars)"; #service.HttpService:JSONEncode(logs)},
				{"Server ID"; serverId},
				"",
				{"JobId"; logs._JobId},
				{"Server Type"; logs._ServerType},
				{"PrivateServerId"; logs._PrivateServerId},
				{"PrivateServerOwnerId"; logs._PrivateServerOwnerId},
				"",
				{"Server Start Time"; service.FormatTime(logs._StartTime, true)},
				{"Server Age"; logs._ServerAge.." min"},
				{"# Unique Joins"; logs._UniqueJoins},
				{"First Join"; logs._FirstJoin},
				"",
				{"Server Country"; logs._ServerCountry},
				}) do
				if type(v) == "table" then
					if not v[2] then continue end
					i += 1
					infoTab:Add("TextLabel", {
						Text = "  "..v[1]..":";
						ToolTip = tostring(v[2]);
						BackgroundTransparency = (i%2 == 0 and 0) or 0.2;
						Size = UDim2.new(1, -10, 0, 26);
						Position = UDim2.new(0, 5, 0, currentPos + 5);
						TextXAlignment = "Left";
					}):Add("TextBox", {
						Text = tostring(v[2]);
						BackgroundTransparency = 1;
						AnchorPoint = Vector2.new(1, 0);
						Size = UDim2.new(1, -150, 1, 0);
						Position = UDim2.new(1, -5, 0, 0);
						TextXAlignment = "Right";
						TextEditable = false;
						ClearTextOnFocus = false;
					})
					currentPos += 26
				else
					currentPos += 8
				end
			end

			infoTab:ResizeCanvas(false, true, false, false, 5, 5)
		end

		for logName, logEntries in pairs(logs) do
			if logName:sub(1, 1) == "_" then continue end

			local quickRef = {}
			if logName == "Server" then
				local MESSAGE_TYPE_COLORS = {
					["MessageError"] = Color3.fromRGB(255, 55, 55),
					["MessageWarning"] = Color3.fromRGB(255, 255, 80),
					["MessageInfo"] = Color3.fromRGB(140, 255, 255)
				}
				for _, log: {Text: string, Type: string, Time: number} in ipairs(logEntries) do
					table.insert(quickRef, {
						Text = string.format("[%s] %s", service.FormatTime(log.Time), log.Text:gsub("\n", "\\n"));
						ToolTip = log.Text;
						Color = MESSAGE_TYPE_COLORS[log.Type];
					})
				end
			else
				for _, log: {Time: number, Text: string?, Desc: string?} in ipairs(logEntries) do
					table.insert(quickRef, {
						Text = string.format("[%s] %s%s", service.FormatTime(log.Time), tostring(log.Text), logName == "Commands" and ": "..log.Desc or "");
						ToolTip = tostring(log.Desc or log.Text);
					})
				end
			end

			local tab = tabFrame:NewTab(logName, {Text = logName;})

			local search = tab:Add("TextBox", {
				Size = UDim2.new(1, 0, 0, 25);
				Position = UDim2.new(0, 0, 0, 5);
				BackgroundTransparency = 0.5;
				BorderSizePixel = 0;
				TextColor3 = Color3.new(1, 1, 1);
				Text = "";
				PlaceholderText = "Search "..#logEntries.." entries";
				TextStrokeTransparency = 0.8;
			})
			search:Add("ImageLabel", {
				Image = client.MatIcons.Search;
				AnchorPoint = Vector2.new(1, 0.5);
				Position = UDim2.new(1, -5, 0.5, 0);
				Size = UDim2.new(0, 18, 0, 18);
				ImageTransparency = 0.2;
				BackgroundTransparency = 1;
			})

			local scroller = tab:Add("ScrollingFrame", {
				List = {};
				ScrollBarThickness = 3;
				BackgroundTransparency = 1;
				Position = UDim2.new(0, 0, 0, 35);
				Size = UDim2.new(1, 0, 1, -35);
			})

			local function list()
				local i = 1
				local filter = search.Text:lower()
				scroller:ClearAllChildren()
				for _, line in ipairs(quickRef) do
					if string.find(line.Text:lower(), filter) or string.find(line.ToolTip:lower(), filter) then
						local entry = scroller:Add("TextButton", {
							AutoButtonColor = false;
							Size = UDim2.new(1, 0, 0, 22);
							Position = UDim2.new(0, 0, 0, 22 * (i-1));
							BackgroundTransparency = (i%2 == 0 and 0.2) or 0.6;
							Text = "  "..line.Text;
							ToolTip = line.ToolTip;
							TextXAlignment = Enum.TextXAlignment.Left;
							TextYAlignment = Enum.TextYAlignment.Top;
							TextTruncate = Enum.TextTruncate.AtEnd;
							TextWrapped = false;
							ZIndex = 2;
							ClipsDescendants = true;
						})
						if line.Color then
							entry.TextColor3 = line.Color
						end
						entry.MouseButton1Click:Connect(function()
							if not entry.Active then return end
							entry.Active = false
							client.UI.Make("Notepad", {
								Text = line.Text..if line.ToolTip then "\n\n"..line.ToolTip else "";
							})
							task.wait(0.5)
							entry.Active = true
						end)
						i += 1
					end
				end
				scroller:ResizeCanvas(false, true, false, false, 5, 5)
			end
			search:GetPropertyChangedSignal("Text"):Connect(list)
			list()
		end

		if placeholder then placeholder:Destroy() end
	end

	task.defer(fetch)

	window:AddTitleButton({
		Text = "";
		OnClick = function()
			if logs then
				if client.UI.Make("YesNoPrompt", {Question = "Print exported log to client output in JSON format?";}) == "Yes" then
					print("\n---- EXPORTED LOG "..serverId.." ----")
					print(service.HttpService:JSONEncode(logs))
					print("\n---- EXPORTED LOG END ----")
				end
			else
				client.UI.Make("Output", {Message = "Log does not exist.";})
			end
		end
	}):Add("ImageLabel", {
		Size = UDim2.new(0, 18, 0, 18);
		Position = UDim2.new(0, 6, 0, 1);
		Image = client.MatIcons.Code;
		BackgroundTransparency = 1;
	})

	window:Ready()
end
