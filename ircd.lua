----------- ircserver.lua

-- Based on The Tcl IRCd (http://www.hping.org/tclircd/) by Salvatore Sanfilippo.
--

local socket = require("socket")
local hostname = "localhost"
local port = 24000
local version = "LuaIRCD"

local ChannelInfo = {}
local ClientMap = {}
local NickToClientInfo = {}

local ChannelPrivateMessage = { }

function newset()
   local reverse = {}
   local set = {}
   setmetatable(set, { __index = {
       insert = function(set, value)
           table.insert(set, value)
         --reverse[value] = table.getn(set)
           reverse[value] = #(set)
           ClientMap[value] =
           {
               Client = value,
               State = "UNREGISTERED",

Host = type(value) == "tcp{client}" and value:getpeername() or "localhost",

               Port = 0,
               Nick = nil,
               User = nil,
               RealName = nil,
               Channels = {},
           }
       end,
       remove = function(set, value)
           local clientInfo = ClientMap[value]
           if clientInfo and clientInfo.Nick then
               NickToClientInfo[clientInfo.Nick] = nil
           end
           table.remove(set, reverse[value])
           reverse[value] = nil
           ClientMap[value] = nil
       end,
   }})
   return set
end

local set = newset()

function ircWrite(clientInfo, text)
   local nick = ""
   if clientInfo then nick = clientInfo.Nick or "" end
   io.write('->' .. nick .. '  ' .. text .. "\n")
   local bytes, error = clientInfo.Client:send(text .. "\r\n")
   if error then
       clientInfo.Client:close()
       io.write("Removing client from set\n")
       set:remove(clientInfo.Client)
   end
end

function SendRawMessage(clientInfo, text)
   ircWrite(clientInfo, ":" .. hostname .. " " .. text)
end


function SendServerClientMessage(clientInfo, code, text)
   local codeStr = tostring(code)
   if codeStr:len() == 1 then
       codeStr = '00' .. codeStr
   elseif codeStr:len() == 2 then
       codeStr = '0' .. codeStr
   end

ircWrite(clientInfo, ":" .. hostname .. " " .. codeStr .. " " .. clientInfo.Nick .. " " .. text)

end


function SendUserMessage(clientInfo, target, text, noSelf)

local userStr = ":" .. clientInfo.Nick .. "!" .. clientInfo.User .. "@" .. clientInfo.Host

   if target:sub(1, 1) == "#" then
       local channel = ChannelInfo[target]
       for _, user in pairs(channel.userList) do
           if noSelf == true  and  user.clientInfo == clientInfo then
           else
               ircWrite(user.clientInfo, userStr .. " " .. text)
           end
       end
   else
       local targetInfo = ClientMap[target]
       if targetInfo then
           ircWrite(targetInfo.Client, userStr .. " " .. text)
       end
   end
end


function Command_JOIN(clientInfo, channels)
   for channelName in channels:gmatch('([^ ,]+),*') do
       local channel = ChannelInfo[channelName]
       if not channel then
           channel =
           {
               topic = "",
               userList = {},
               numUsers = 0,
               name = channelName,
           }
           ChannelInfo[channelName] = channel
       end

       local channelUser = channel.userList[clientInfo]
       if not channelUser then
           clientInfo.Channels[channelName] = channel

channel.userList[clientInfo] = { clientInfo = clientInfo, mode = channel.numUsers > 0 and "" or "@" }

           channel.numUsers = channel.numUsers + 1
           SendUserMessage(clientInfo, channelName, "JOIN " .. channelName)
           Command_TOPIC(clientInfo, channelName .. " :" .. channel.topic)
           Command_NAMES(clientInfo, channelName)
       end
   end
end



function Command_LIST(clientInfo, args)
   local target
   if args then
       local _, _, target = args:find("^:%s*(.+)%s*$")
   end
   for channelName, channel in pairs(clientInfo.Channels) do

SendServerClientMessage(clientInfo, 322, channelName .. " " .. channel.numUsers .. " :" .. channel.topic)

   end
   SendServerClientMessage(clientInfo, 323, ":End of LIST")
end


function Command_MODE(clientInfo, args)
   if not args then return end
   local _, _, target, mode = args:find("^+([^ ]+) *(.*)$")
   if not target then return end

   local args = {}
   for arg in mode:gfind('([^ ]+) *') do
       table.insert(args, arg)
   end

   if target:sub(1, 1) == '#' then
       local channel = ChannelInfo[target]
       if args[1] == '+o' or args[1] == '-o' then
           local modeClient = NickToClientInfo[args[2]]
           if not modeClient then return end

           local channelUser = channel.userList[clientInfo]
           if not channelUser then return end
           if channelUser.mode ~= '@' then

SendServerClientMessage(clientInfo, 482, target .. " :You're not channel operator")

               return
           end

           local modeUser = channel.userList[modeClient]
           modeUser.mode = arg[1] == '+o' and '@' or ''

SendUserMessage(clientInfo, target, "MODE " .. target .. " " .. mode)

       else
           SendServerClientMessage(clientInfo, 324, target)
       end
   end
end


function Command_NICK(clientInfo, nick)
   if not nick then return end
   local oldNick = clientInfo.Nick
   if NickToClientInfo[nick] then

SendRawMessage(clientInfo, "433 * " .. nick .. " :Nickname is already in use")

       return
   end
   for channelName, channel in pairs(clientInfo.Channels) do
       SendUserMessage(clientInfo, channelName, "NICK " .. nick)
   end
   clientInfo.Nick = nick
   NickToClientInfo[nick] = NickToClientInfo[oldNick]
   NickToClientInfo[oldNick] = nil
end


function Command_NAMES(clientInfo, channelName)
   if not channelName then return end
   local channel = ChannelInfo[channelName]
   if channel then
       local users = ""
       for userClientInfo, user in pairs(channel.userList) do
           users = users .. user.mode .. userClientInfo.Nick .. " "
       end

SendServerClientMessage(clientInfo, 353, "= " .. channel.name .. " :" .. users)

   end

SendServerClientMessage(clientInfo, 366, channelName .. " :End of /NAMES list.")

end


function Command_NOTICE(clientInfo, args)
   if not args then return end
   local _, _, target, message = args:find("^([^ ]+) +:(.*)$")
   if not target then return end

SendUserMessage(clientInfo, target, "NOTICE " .. target .. " :" .. message, true)

end


function Command_PART(clientInfo, args, command, text)
   if not args then return end
   local _, _, target, message = args:find("^([^ ]+) +(.*)$")
   if not target then return end

   for channelName in args:gfind('(#%w+),-') do
       local channel = ChannelInfo[channelName]
       if channel then
           if command == "QUIT" then

SendUserMessage(clientInfo, channelName, "QUIT " .. text, true)

           elseif command then

SendUserMessage(clientInfo, channelName, command .. " " .. channelName .. " " .. message)

           end

           clientInfo.Channels[channelName] = nil
           channel.userList[clientInfo] = nil
           channel.numUsers = channel.numUsers - 1
           if channel.numUsers == 0 then
               ChannelInfo[channel] = nil
           end
       end
   end
end


function Command_PING(clientInfo, message)
   SendRawMessage(clientInfo, "PONG " .. hostname .. " " .. message)
end


function Command_PONG(clientInfo, message)
end


function Command_PRIVMSG(clientInfo, args)
   if not args then return end
   local _, _, target, message = args:find("^([^ ]+) +:(.*)$")
   if not target then return end

SendUserMessage(clientInfo, target, "PRIVMSG " .. target .. " :" .. message, true)

   if not inPrivateMessage then
       local func = ChannelPrivateMessage[target]
       if func then
           inPrivateMessage = true
           curClientInfo = clientInfo
           curTarget = target
           func(clientInfo, target, message)
           inPrivateMessage = nil
       end
   end
end


function Command_QUIT(clientInfo, message)
   for channelName, channel in pairs(clientInfo.Channels) do
       if channel.userList[clientInfo] then
           Command_PART(clientInfo, channelName, "QUIT", message)
       end
   end

   if clientInfo.Nick then
       NickToClientInfo[clientInfo.Nick] = nil
   end
   clientInfo.Client:close()
   set:remove(clientInfo.Client)
end


function Command_TOPIC(clientInfo, args)
   print("Topic args: " .. args)
   local _, _, target, topic = args:find("^([^ ]+) +:%s*(.*)%s*$")
   if not target then return end
   local channel = ChannelInfo[target]
   if not channel then return end
   channel.topic = topic
   if channel.topic == "" then

SendServerClientMessage(clientInfo, 331, channel.name .. " :No topic is set")

   else

SendServerClientMessage(clientInfo, 332, channel.name .. " :" .. channel.topic)

   end
end


function Command_USERHOST(clientInfo, args)
   if not args then return end
   local _, _, nicks = args:find(":(.+)")
   if not nicks then return end
   local text = ""
   for nick in nicks:gfind('(.*) -') do
       local nickClient = NickToClientInfo[nick]
       if nickClient then
           local nickInfo = ClientMap[nickClient]

text = text .. nick .. "=+" .. nickClient.User .. "@" .. nickClient.Host .. " "

       end
   end
   SendServerClientMessage(clientInfo, 302, ":" .. text)
end


function Command_WHO(clientInfo, args)
   local _, _, channel = args:find("WHO (.*) (.*)$")
   if channel then
       handleClientWho(clientInfo, channel)
--[[

foreach {topic userlist usermode} [channelInfoOrReturn $fd $channel] break

       foreach userfd $userlist mode $usermode {

SendServerClientMessage $fd 352 "$channel ~[clientUser $userfd] [clientHost $userfd] [config hostname] $mode[clientNick $userfd] H :0 [clientRealName $userfd]"

       }
       SendServerClientMessage $fd 315 "$channel :End of /WHO list."]]
       return
   end
end


function Command_WHOIS(clientInfo, nick)
   if not nick then return end
   local targetInfo = ClientMap[nick]
   if targetInfo then

SendServerClientMessage(clientInfo, 311, nick .. " ~" .. targetInfo.User .. " " .. targetInfo.Host .. " * :" .. targetInfo.RealName)

       local chans = ""
       for channelName, channel in pairs(targetInfo.Channels) do
           chans = chans .. channelName .. " "
       end
       if chans:len() > 1 then
           SendServerClientMessage(clientInfo, 319, nick .. " :" .. chans)
       end

SendServerClientMessage(clientInfo, 312, nick .. " " .. hostname .. " :" .. hostname)

   end

SendServerClientMessage(clientInfo, 318, nick .. " :End of /WHOIS list.")

end


local CommandDispatch =
{
   PING = Command_PING,
   PONG = Command_PONG,
   MODE = Command_MODE,
   JOIN = Command_JOIN,
   PART = Command_PART,
   PRIVMSG = Command_PRIVMSG,
   NOTICE = Command_NOTICE,
   QUIT = Command_QUIT,
   NICK = Command_NICK,
   TOPIC = Command_TOPIC,
   LIST = Command_LIST,
   WHOIS = Command_WHOIS,
   WHO = Command_WHO,
   USERHOST = Command_USERHOST,
}


function ProcessClient(clientInfo)
   local line, error = clientInfo.Client:receive()
   if error == 'closed' then
       Command_QUIT(clientInfo, error .. " from client")
   end

   if not line or line == "" then
       return
   end

   local _, _, line = line:find("%s*(.+)%s*")

print(clientInfo.State .. ": " .. (clientInfo.Nick or "") .. " -> '" .. line .. "'")

   if clientInfo.State == "UNREGISTERED" then
       local _, _, nick = line:find("NICK (.+)")
       if nick then
           if NickToClientInfo[nick] then

SendRawMessage(clientInfo, "433 * " .. nick .. " :Nickname is already in use")

               return
           end

           clientInfo.Nick = nick
       end

local _, _, user, mode, virtualHost, realName = line:find("USER (.*) (.*) (.*) :(.+)$")

       if user then
           clientInfo.User = user
           clientInfo.Host = virtualHost
           clientInfo.RealName = realName
       end

       if clientInfo.Nick and clientInfo.User then
           clientInfo.State = "REGISTERED"

SendServerClientMessage(clientInfo, 001, "Welcome to the LuaIRC server " .. clientInfo.Nick .. "!" .. clientInfo.User .. "@" .. clientInfo.Host) SendServerClientMessage(clientInfo, 002, "Your host is " .. hostname .. ", running version " .. version) SendServerClientMessage(clientInfo, 003, "This server was created ...") SendServerClientMessage(clientInfo, 004, hostname .. " " .. version .. " aAbBcCdDeEfFGhHiIjkKlLmMnNopPQrRsStUvVwWxXyYzZ0123459*@ bcdefFhiIklmnoPqstv")

           NickToClientInfo[clientInfo.Nick] = clientInfo
       end

---------------------------------------------------------------------------

   elseif clientInfo.State == "REGISTERED" then
       local _, _, command, args = line:find("^%s*([^ ]+) *(.*)%s*$")
       command = command:upper()
       local func = CommandDispatch[command]
       if type(func) == "function" then
           func(clientInfo, args)
       else

SendServerClientMessage(clientInfo.Client, 421, line .. " :Unknown command")

       end
   end
end


function RunServer()
   io.write("Opening server...\n")
   local server = assert(socket.bind(hostname, port))
   server:settimeout(1) -- make sure we don't block in accept
   set:insert(server)

   while 1 do
       local readable, _, error = socket.select(set, nil)
       for _, input in ipairs(readable) do
           -- is it a server socket?
           if input == server then
               io.write("Waiting for clients\n")
               local new = input:accept()
               if new then
                   new:settimeout(1)
                   io.write("Inserting client in set\n")

SendRawMessage({ Client = new }, "NOTICE AUTH :" .. version .. " initialized.")

                   set:insert(new)
               end
           else
               ProcessClient(ClientMap[input])
           end
       end
   end
end

local ircPrint = function(...)

SendUserMessage(curClientInfo, curTarget, 'PRIVMSG ' .. curTarget .. " :" .. arg[1])

end

ChannelPrivateMessage['#lua'] = function(clientInfo, target, message)
   local chunk = loadstring(message)
   if chunk then
       savePrint = print
       print = ircPrint
       pcall(chunk)
       print = savePrint
   end
end

RunServer()



