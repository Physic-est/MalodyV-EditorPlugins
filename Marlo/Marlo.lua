-- =========================================================
-- Author: Physic
-- Version: 1.0.0
-- LastEditTime: 2025-09-14
-- =========================================================

------------------------------------------------------------
-- プラグイン情報
------------------------------------------------------------
PluginName = 'Marlo~'
PluginMode = 7
PluginType = 0
PluginRequire = '6.5.12'

function Run()
    local time = Editor:GetSystemTime()
    local marlo = Editor:AddSprite('marlo-' .. time, 'editor-marlo.png')
    marlo.X = math.random(0, 100)
    marlo.Beat = Editor:BeatAdd(Editor:GetCurrentBeat(), Editor:MakeBeat(math.random(1,4),1, math.random(1,4)))
end