require("CFN/Home/Main")
require("CFN/Home/Options")

local onBoot = function()
    local o = PZAPI.ModOptions:getOptions(CFN.Home.Identity)
    if not o then
        return
    end

    o:addTitle("UI_CFN_Home_Option_TitleFastZones")

    o:addKeyBind("RoomToZoneKey", "UI_CFN_Home_Option_RoomToZoneKey", 55, "UI_CFN_Home_Option_RoomToZoneKey_tooltip")
    o:addKeyBind("BuildingToZoneKey", "UI_CFN_Home_Option_BuildingToZoneKey", 181,
        "UI_CFN_Home_Option_BuildingToZoneKey_tooltip")
end

Events.OnGameBoot.Add(onBoot)
