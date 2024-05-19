-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Decides the next action based on player proximity.
-- If any player is within range, it initiates an attack; otherwise, moves randomly.
function decideNextAction()
  local protagonist = LatestGameState.Players[ao.id]
  
  local attackRange = 1  -- Jarak serang sesuai dengan kode permainan
  local moveDistance = 1 -- Jarak gerak saat bergerak

  -- Direction map for movements
  local directionMap = {
      ["0,1"] = "Up",
      ["0,-1"] = "Down",
      ["-1,0"] = "Left",
      ["1,0"] = "Right",
      ["1,1"] = "UpRight",
      ["-1,1"] = "UpLeft",
      ["1,-1"] = "DownRight",
      ["-1,-1"] = "DownLeft"
  }

  -- Mencari pemain dalam jarak serang
  local targetInRange = false
  for target, player in pairs(LatestGameState.Players) do
      if target ~= ao.id and inRange(protagonist.x, protagonist.y, player.x, player.y, 1) then
        targetInRange = true
        break
      end
  end

  -- Jika ada pemain dalam jarak serang, serang
  -- Jika tidak ada pemain dalam jarak serang, bergerak secara acak
  local dx = math.random(-1, 1)
  local dy = math.random(-1, 1)
  local directionKey = tostring(dx) .. "," .. tostring(dy)
  local direction = directionMap[directionKey]

  if targetInRange and protagonist.energy > 5 then
    print(colors.red .. "Attacking nearby player" .. colors.reset)
    ao.send({Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(protagonist.energy)})
  elseif direction and targetInRange and protagonist.energy <= 5 then
    print(colors.red .. "I need to rest, let me fly away to " ..direction .. "(" .. protagonist.x .. ", " .. protagonist.y .. ")" .. colors.reset)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = direction})
  elseif direction then
    print(colors.blue .. "Moving " .. direction .. " to (" .. protagonist.x .. ", " .. protagonist.y .. ")" .. colors.reset)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = direction})
  else
    print(colors.gray .. "No valid direction found for movement." .. colors.reset)
  end

  InAction = false -- Reset InAction flag after performing the action
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true -- InAction logic added
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then -- InAction logic added
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Jika ejected
Handlers.add(
  "Reregister",
  Handlers.utils.hasMatchingTag("Action", "Ejected"),
  function (msg)
      print(colors.green .. "Reregister.." .. colors.reset)
      ao.send({Target = Game, Action = "Register"})
  end
)

--- Jika telah menyerang
Handlers.add(
  "SuccessfulAtack",
  Handlers.utils.hasMatchingTag("Action", "Successful-Hit"),
  function ()
    print(colors.red .. "You almost die madafaka!!!" .. colors.reset)
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false -- InAction logic added
      return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == nil then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        print(colors.red .. "Returning attack." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
      end
      InAction = false -- Reset InAction flag after performing the action
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
