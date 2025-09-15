-- =========================================================
-- Author: Physic
-- Version: 1.0.0
-- LastEditTime: 2025-09-15
-- =========================================================

------------------------------------------------------------
-- プラグイン情報
------------------------------------------------------------
PluginName = 'ReShape'
PluginMode = 7
PluginType = 0
PluginRequire = '6.4.2'

------------------------------------------------------------
-- グローバル変数定義
------------------------------------------------------------
local NoteType = {
    Tap = 1,
    Wipe = 1024,
    Slide = 2048
}

local SampleCount = 1000

function Run()
    local selectedNotes = Editor:GetSelectNotes()
    local selectedNote = selectedNotes[0]
    local notesCount = selectedNotes == nil and 0 or selectedNotes.Length
    local head = nil
    local tail = nil
    local originalSegments = {}
    local samples = {}

    if notesCount ~= 1 then
        Editor:ShowMessage("Please select one slide note !")
        return
    end

    -- Slide 以外の場合は考慮しない
    if Editor:GetNoteType(selectedNote) ~= NoteType.Slide then
        Editor:ShowMessage("Please select one slide note !")
        return
    end

    Editor:StartBatch()

    -- 始点の情報を保存
    -- 始点BeatとPointを取得
    local headBeat = Editor:GetNoteBeat(selectedNote, true)
    local headPoint = BeatToPoint(headBeat)
    local headX = Editor:GetNoteX(selectedNote)
    table.insert(originalSegments, {
        X = headX,
        Y = headPoint,
        Beat = headBeat
    })

    -- セグメント情報を保存
    local segmentsCount = Editor:GetNoteSlideBodyCount(selectedNote)
    for seg = 0, segmentsCount - 1 do
        local segBeat = Editor:BeatAdd(headBeat, Editor:GetNoteSlideBodyBeat(selectedNote, seg))
        local segPoint = BeatToPoint(segBeat)
        local segX = headX + Editor:GetNoteSlideBodyX(selectedNote, seg)
        table.insert(originalSegments, {
            X = segX,
            Y = segPoint,
            Beat = segBeat
        })
    end

    head = originalSegments[1]
    tail = originalSegments[#originalSegments]

    -- 線形補間で細かくサンプリング
    for s = 1, SampleCount do
        -- s時点でのBeat, Xを計算
        local beat = InterpolateBeat(head.Beat, tail.Beat, s / SampleCount)
        local x = LinearInterpolateAlongPoints(originalSegments, beat)
        samples[s] = { X = x, Y = BeatToPoint(beat), Beat = beat }
    end

    Editor:DeleteNoteSlideBody(selectedNote)

    -- 等間隔で再分割
    local divideCount = Editor:GetCurrentDivide()
    local totalPoint = tail.Y - head.Y
    local segmentsCount = (divideCount * math.floor(totalPoint)) + math.floor(divideCount * (totalPoint - math.floor(totalPoint)))
    for i = 1, segmentsCount do
        local t = i / segmentsCount
        local targetPoint = head.Y + (tail.Y - head.Y) * t
        local targetBeat = PointToBeat(targetPoint)

        -- サンプルから一番近いPointを持つ点を探す
        for j = 1, #samples - 1 do
            if samples[j].Y <= targetPoint and targetPoint <= samples[j + 1].Y then
                -- Xを再計算
                local bodyX = samples[j].X - head.X
                Editor:AddNoteSlideBody(selectedNote, Editor:BeatMinus(targetBeat, head.Beat))
                Editor:SetNoteSlideBodyX(selectedNote, i - 1, math.floor(bodyX))
                break
            end
        end
    end

    Editor:FinishBatch()
end

------------------------------------------------------------
-- Utilities
------------------------------------------------------------

function BeatToPoint(beat)
    return beat.beat + (beat.numor / beat.denom)
end

function PointToBeat(point)
    local beat = math.floor(point)
    local numor = math.floor((point - beat) * 1000)
    local denom = 1000
    return { beat = beat, numor = numor, denom = denom }
end

---2つのBeatをt(0～1)で線形補間して返す
---@param beat1 any 始点のBeat
---@param beat2 any 終点のBeat
---@param t number 0.0-1.0の補間係数
---@return table
function InterpolateBeat(beat1, beat2, t)
    local point1 = BeatToPoint(beat1)
    local point2 = BeatToPoint(beat2)
    local f = point1 + ((point2 - point1) * t)
    return PointToBeat(f)
end

---点列(points)上で指定Beat時点のX座標を線形補間で求める
---@param points any
---@param targetBeat any
---@return integer 対象Beat時点のX座標
function LinearInterpolateAlongPoints(points, targetBeat)
    local pointT = BeatToPoint(targetBeat)
    for i = 1, #points - 1 do
        local pointA = BeatToPoint(points[i].Beat)
        local pointB = BeatToPoint(points[i + 1].Beat)
        if pointA <= pointT and pointT <= pointB then
            local t = (pointT - pointA) / (pointB - pointA)
            return points[i].X + (points[i + 1].X - points[i].X) * t
        end
    end

    if pointT <= BeatToPoint(points[1].Beat) then
        -- 始点をそのまま返す
        return points[1].X
    else
        -- 終点をそのまま返す
        return points[#points].X
    end
end
