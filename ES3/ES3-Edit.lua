-- =========================================================
-- Author: Physic
-- Version: 1.0.0
-- LastEditTime: 2026-09-18
-- =========================================================
-- Extra-Slide v3 の空中要素を選ぶ・動かす・消すプラグイン。
--
--   タップ                  一番近い要素を選ぶ
--   選んである要素をタップ  消す（2手にしてあるのは、タッチで誤って消さないため）
--   何も無いところをタップ  選択を外す
--   細い芯の端をドラッグ    時刻を伸ばす／縮める
--   頭・尻尾の幅の部分をドラッグ  **幅を変える**（中心は動かさない）
--   芯の真ん中をドラッグ    全体を動かす
--
-- 帯は芯を細く、頭と尻尾だけ幅を持たせて描いてある。掴み分けもその見た目に合わせてある
--
-- キーボードは使わなくても全部できる（モバイル想定）。
-- =========================================================

------------------------------------------------------------
-- プラグイン情報
------------------------------------------------------------
PluginName = 'ES3 Edit'
PluginMode = 7
PluginType = 2
PluginRequire = '6.4.2'
PluginIcon = 'ES3-Edit.png'

-- >>> LANE3D COMMON BEGIN
------------------------------------------------------------
-- 定数
------------------------------------------------------------
local L3D = {
    SrcFile  = 'lane3d.src',        -- 拍で持つソース（正）
    ExFile   = 'lane3d.ex',         -- スキンが読む生成物（ms）
    DataKey  = 'lane3d-src',        -- プラグイン間の共有データ
    UndoKey  = 'lane3d-undo',
    Psw      = 'lane3d-extra-slide-v3',
    Denom    = 96,                  -- 拍の分母。/2 /3 /4 /6 /8 /12 /16 /24 /32 /48 が乗る
    UndoMax  = 10,
    SnapBeat = 0.125,               -- 繋ぎ目スナップ（拍）
    SnapX    = 16,                  -- 繋ぎ目スナップ（譜面x）
    LaneW    = 64,                  -- 1レーンの幅。ジェスチャの縦横判定にも使う
    BodyW    = 10,                  -- 帯の芯の太さ（譜面x単位）。幅は頭と尻尾だけで見せる
    Img      = 'editor-es3-fill.png',
    Version  = '1.0.0',
}

-- 拡張ファイルで幅と ease を省略したときの値。ES3-Config で変える。
-- xgrid は横方向のスナップ。-1 = 自動（譜面のノーツから推定）/ 0 = スナップしない / N = N列に固定
local L3DConfig = { width = 64, ease = 0, xgrid = -1 }

local L3DCamRange = {
    angle = { 5, 85 },
    x     = { -255, 510 },
    y     = { 40, 2000 },
    z     = { 120, 4000 },
    roll  = { -360, 360 },
    zoom  = { 0.2, 5 },
    -- Roll の回転軸の画面Y。書かなければスキンの設定に従う
    rollpivot = { -3000, 3000 },
}

local L3DColor = {
    tap   = { 120, 230, 255 },
    up    = { 150, 115, 255 },
    down  = { 255, 170,  90 },
    slide = { 110, 210, 255 },
    cap   = { 255, 255, 255 },
    cam   = { 120, 255, 180 },
    bad   = { 255,  90,  90 },
    sel   = { 255, 240, 120 },
}

------------------------------------------------------------
-- 小物
------------------------------------------------------------
local function L3DNum(v)
    if v == nil then return '0' end
    local r = math.floor(v + 0.5)
    if math.abs(v - r) < 0.0005 then return string.format('%d', r) end
    local s = string.format('%.3f', v)
    s = string.gsub(s, '0+$', '')
    s = string.gsub(s, '%.$', '')
    return s
end

local function L3DClamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function L3DLines(text)
    local out = {}
    if text == nil then return out end
    local pattern = '[^' .. string.char(13) .. string.char(10) .. ']+'
    for line in string.gmatch(text, pattern) do
        out[#out + 1] = line
    end
    return out
end

local function L3DFields(line)
    local f = {}
    for v in string.gmatch(line, '[^,]+') do
        f[#f + 1] = (string.gsub(v, '^%s*(.-)%s*$', '%1'))
    end
    return f
end

------------------------------------------------------------
-- 拍
------------------------------------------------------------
local function L3DBeatToPoint(b)
    if b == nil then return 0 end
    if type(b) == 'number' then return b end
    local d = b.denom
    if d == nil or d == 0 then d = 1 end
    return b.beat + (b.numor / d)
end

local function L3DPointToBeat(p)
    local total = math.floor(p * L3D.Denom + 0.5)
    local b = math.floor(total / L3D.Denom)
    return { beat = b, numor = total - b * L3D.Denom, denom = L3D.Denom }
end

local function L3DFormatBeat(p)
    local bt = L3DPointToBeat(p)
    return string.format('%d:%d/%d', bt.beat, bt.numor, bt.denom)
end

local function L3DParseBeat(s)
    if s == nil then return nil end
    local b, n, d = string.match(s, '^(-?%d+):(%d+)/(%d+)$')
    if b ~= nil then
        d = tonumber(d)
        if d == nil or d == 0 then return nil end
        return tonumber(b) + tonumber(n) / d
    end
    return tonumber(s)
end

------------------------------------------------------------
-- エディターの刻みに合わせる
--
-- 縦（拍）: GetClickBeat() が現在の分割（GetCurrentDivide）に合わせた値を返す。
--           GetClickBeatFree() は分割を無視して 1/32 に丸めるので使わない。
-- 横（x）: **エディターの横グリッドの倍率を読む API が無い**（CallShortcut(39/40) で
--           変えられるだけで getter が無い）。そこで譜面に既にあるノーツの x から
--           使われているグリッドを推定する。ES3 Config で固定もできる。
--           Slide 譜面の x は 0〜255 で、4列なら 31/95/159/223（= 255*(k+0.5)/4 の切り捨て）
------------------------------------------------------------
local L3DGrid = { n = 0, mode = 'none' }   -- mode: 'center'（区画の中心）/ 'edge'（区画の境目）

local function L3DGridPos(n, mode, k)
    if mode == 'center' then
        return math.floor(255 * (k + 0.5) / n)
    end
    return math.floor(255 * k / n + 0.5)
end

--- 譜面のノーツの x から、使われている横グリッドを当てる
local function L3DDetectGrid()
    local seen, list = {}, {}
    pcall(function()
        local count = Editor:GetNoteCount()
        for i = 0, count - 1 do
            local id = Editor:GetNoteAt(i)
            if id ~= nil and id >= 0 then
                local x = Editor:GetNoteX(id)
                if x ~= nil and x >= 0 and x <= 255 and not seen[x] then
                    seen[x] = true
                    list[#list + 1] = x
                end
            end
        end
    end)
    if #list < 3 then return { n = 0, mode = 'none' } end

    local best = { n = 0, mode = 'none', score = 0 }
    local modes = { 'center', 'edge' }
    -- 粗いほうから見て、同じ当たり方なら粗いグリッドを採る
    for n = 2, 32 do
        for m = 1, 2 do
            local mode = modes[m]
            local hit = 0
            for i = 1, #list do
                local x = list[i]
                local k = math.floor(x * n / 255 + 0.5)
                -- 切り捨てと四捨五入の差で1ずれることがあるので、前後の格子点も見る
                for d = -1, 1 do
                    if math.abs(L3DGridPos(n, mode, k + d) - x) <= 1 then
                        hit = hit + 1
                        break
                    end
                end
            end
            local score = hit / #list
            if score > best.score + 0.001 then
                best = { n = n, mode = mode, score = score }
            end
        end
    end
    -- ほとんど当たっていないなら、自由に置かれた譜面とみてスナップしない
    if best.score < 0.9 then return { n = 0, mode = 'none' } end
    return best
end

--- 使う横グリッドを決める。ES3 Config の設定が優先
local function L3DPrepareGrid()
    if L3DConfig.xgrid == 0 then
        L3DGrid = { n = 0, mode = 'none' }
    elseif L3DConfig.xgrid ~= nil and L3DConfig.xgrid > 0 then
        L3DGrid = { n = L3DConfig.xgrid, mode = 'center' }
    else
        L3DGrid = L3DDetectGrid()
    end
    return L3DGrid
end

local function L3DGridLabel()
    if L3DGrid.n <= 0 then return 'なし' end
    local how = '中心'
    if L3DGrid.mode == 'edge' then how = '境目' end
    if L3DConfig.xgrid ~= nil and L3DConfig.xgrid > 0 then
        return string.format('%d列(指定)', L3DGrid.n)
    end
    return string.format('%d分割の%s', L3DGrid.n, how)
end

--- x をグリッドに載せる
local function L3DSnapX(x)
    local n = L3DGrid.n
    if n == nil or n <= 0 then return x end
    local k
    if L3DGrid.mode == 'center' then
        k = math.floor(x * n / 255)
        if k < 0 then k = 0 end
        if k > n - 1 then k = n - 1 end
    else
        k = math.floor(x * n / 255 + 0.5)
        if k < 0 then k = 0 end
        if k > n then k = n end
    end
    return L3DGridPos(n, L3DGrid.mode, k)
end

--- 拍を現在の分割に載せる
local function L3DSnapBeat(p)
    local d = 4
    pcall(function() d = Editor:GetCurrentDivide() end)
    if d == nil or d <= 0 then d = 4 end
    return math.floor(p * d + 0.5) / d
end

--- クリック位置。縦は現在の分割、横はグリッドに載せて返す。置くときに使う
local function L3DClickPos()
    local x = Editor:GetClickX()
    if x == nil or x < 0 or x > 255 then return nil end
    return L3DSnapX(x), L3DBeatToPoint(Editor:GetClickBeat())
end

--- 横をスナップしないクリック位置。**当たり判定に使う**。
--- スナップした値で当たりを見ると、4列グリッドではどこを押しても列の中心に吸われるので、
--- 「要素の端を掴む」ができなくなる（縦は分割に載せたままでよい）
local function L3DClickRaw()
    local x = Editor:GetClickX()
    if x == nil or x < 0 or x > 255 then return nil end
    return x, L3DBeatToPoint(Editor:GetClickBeat())
end

------------------------------------------------------------
-- 拍 <-> ms
--   BPM の列から相対 ms を積み、既存ノーツ1つ（拍と ms の両方が取れる）で原点を合わせる。
--   ノーツが1つも無い譜面では原点が取れないので calibrated = false を返す
------------------------------------------------------------
local function L3DRelMs(segs, p)
    local seg = segs[1]
    for i = 1, #segs do
        if segs[i].p <= p then seg = segs[i] else break end
    end
    return seg.ms + (p - seg.p) * 60000 / seg.bpm
end

local function L3DBuildTiming()
    local segs = {}
    pcall(function()
        local n = Editor:GetTimeCount()
        for i = 0, n - 1 do
            local t = Editor:GetTimeAt(i)
            if t ~= nil and t.bpm ~= nil and t.bpm > 0 then
                segs[#segs + 1] = { p = L3DBeatToPoint(t.beat), bpm = t.bpm }
            end
        end
    end)
    if #segs == 0 then segs[1] = { p = 0, bpm = 120 } end
    table.sort(segs, function(a, b) return a.p < b.p end)
    if segs[1].p > 0 then
        table.insert(segs, 1, { p = 0, bpm = segs[1].bpm })
    end
    segs[1].ms = 0
    for i = 2, #segs do
        local q = segs[i - 1]
        segs[i].ms = q.ms + (segs[i].p - q.p) * 60000 / q.bpm
    end

    local base, calibrated = 0, false
    pcall(function()
        local count = Editor:GetNoteCount()
        for i = 0, count - 1 do
            local id = Editor:GetNoteAt(i)
            if id ~= nil and id >= 0 then
                local nb = Editor:GetNoteBeat(id, true)
                local nt = Editor:GetNoteTime(id, true)
                if nb ~= nil and nt ~= nil and nt >= 0 and nb.beat ~= nil and nb.beat >= 0 then
                    base = nt - L3DRelMs(segs, L3DBeatToPoint(nb))
                    calibrated = true
                    return
                end
            end
        end
    end)
    return { segs = segs, base = base, calibrated = calibrated }
end

local function L3DBeatMs(timing, p)
    return timing.base + L3DRelMs(timing.segs, p)
end

local function L3DMsBeat(timing, ms)
    local segs = timing.segs
    local rel = ms - timing.base
    local seg = segs[1]
    for i = 1, #segs do
        if segs[i].ms <= rel then seg = segs[i] else break end
    end
    return seg.p + (rel - seg.ms) * seg.bpm / 60000
end

-- その拍における1拍の長さ(ms)。規約Cは拍で見るので使わないが、書き出しの確認に使う
local function L3DBpmAt(timing, p)
    local seg = timing.segs[1]
    for i = 1, #timing.segs do
        if timing.segs[i].p <= p then seg = timing.segs[i] else break end
    end
    return seg.bpm
end

------------------------------------------------------------
-- 要素
--   { kind = 'airtap',   b1, x1, w }
--   { kind = 'airlift',  b1, b2, x1, dir, ease, w }
--   { kind = 'airslide', b1, b2, x1, x2, ease, w }
--   { kind = 'measure',  mb, beats }            mb は時刻ではなく拍
--   { kind = 'cam',      b1, b2, ch, v1, v2, ease }
------------------------------------------------------------
local function L3DIsBand(e)
    return e.kind == 'airlift' or e.kind == 'airslide'
end

--- 長さを持たない Lift（直角の上げ下ろし）。判定を持たない見た目だけの継ぎ目
local function L3DIsInstant(e)
    return e.kind == 'airlift' and e.b2 ~= nil and (e.b2 - e.b1) < 1 / L3D.Denom
end

-- 帯の時刻 p における x
local function L3DEase(u, k)
    if u < 0 then u = 0 end
    if u > 1 then u = 1 end
    if k == 1 then return u * u end
    if k == 2 then return 1 - (1 - u) * (1 - u) end
    if k == 3 then return u * u * (3 - 2 * u) end
    return u
end

local function L3DBandX(e, p)
    if e.kind == 'airlift' then return e.x1 end
    if e.b2 <= e.b1 then return e.x2 end
    return e.x1 + (e.x2 - e.x1) * L3DEase((p - e.b1) / (e.b2 - e.b1), e.ease or 0)
end

--- 要素の時刻 p における中心 x。AirTap は b2 を持たないので L3DBandX に渡せない
local function L3DElemX(e, p)
    if e.kind == 'airtap' then return e.x1 end
    if e.b2 == nil then return e.x1 end
    return L3DBandX(e, L3DClamp(p, e.b1, e.b2))
end

--- 幅を横グリッドの刻みに載せる。グリッドが無ければ 8 刻み
local function L3DSnapWidth(w)
    local step = 8
    if L3DGrid.n ~= nil and L3DGrid.n > 0 then step = 255 / L3DGrid.n end
    local k = math.floor(w / step + 0.5)
    if k < 1 then k = 1 end
    local v = math.floor(k * step + 0.5)
    if v > 255 then v = 255 end
    return v
end

local function L3DSortElements(list)
    table.sort(list, function(a, b)
        local pa = a.b1 or a.mb or 0
        local pb = b.b1 or b.mb or 0
        if pa ~= pb then return pa < pb end
        return tostring(a.kind) < tostring(b.kind)
    end)
end

------------------------------------------------------------
-- ソースの読み書き
------------------------------------------------------------
local function L3DReadFileSafe(name)
    local txt = nil
    pcall(function() txt = Editor:ReadFile(name) end)
    if txt == nil or txt == '' then return nil end
    return txt
end

local function L3DWriteFileSafe(name, text)
    return pcall(function() Editor:WriteFile(name, text) end)
end

local function L3DReadData(key)
    local v = nil
    pcall(function() v = Editor:ReadData(key, L3D.Psw) end)
    if v == nil or v == '' then return nil end
    return v
end

local function L3DWriteData(key, text)
    return pcall(function() Editor:WriteData(key, L3D.Psw, text) end)
end

-- 1行を要素にする。戻り値は要素 or nil, エラー文
local function L3DParseLine(f, beatMode, timing)
    local kind = f[1]
    local function toB(i)
        if beatMode then return L3DParseBeat(f[i]) end
        local ms = tonumber(f[i])
        if ms == nil or timing == nil then return nil end
        return L3DMsBeat(timing, ms)
    end
    local function toN(i) return tonumber(f[i]) end
    local function inX(v) return v ~= nil and v >= 0 and v <= 255 end

    if kind == 'airtap' then
        local b, x = toB(2), toN(3)
        if b == nil or not inX(x) then return nil, '書式は airtap,時刻,x[,幅]' end
        return { kind = 'airtap', b1 = b, x1 = x, w = toN(4) or L3DConfig.width }
    elseif kind == 'airlift' then
        local b1, b2, x, dir = toB(2), toB(3), toN(4), f[5]
        if b1 == nil or b2 == nil or not inX(x) or (dir ~= 'up' and dir ~= 'down') then
            return nil, '書式は airlift,開始,終了,x,up|down[,ease[,幅]]'
        end
        -- 開始 == 終了 は「直角」。その瞬間に床 <-> 空中を移る継ぎ目
        if b2 < b1 then return nil, '終了が開始より前' end
        return { kind = 'airlift', b1 = b1, b2 = b2, x1 = x, dir = dir,
                 ease = toN(6) or 0, w = toN(7) or L3DConfig.width }
    elseif kind == 'airslide' then
        local b1, b2, x1, x2 = toB(2), toB(3), toN(4), toN(5)
        if b1 == nil or b2 == nil or not inX(x1) or not inX(x2) then
            return nil, '書式は airslide,開始,終了,x1,x2[,ease[,幅]]'
        end
        if b2 <= b1 then return nil, '終了が開始以前' end
        return { kind = 'airslide', b1 = b1, b2 = b2, x1 = x1, x2 = x2,
                 ease = toN(6) or 0, w = toN(7) or L3DConfig.width }
    elseif kind == 'measure' then
        local mb, beats = tonumber(f[2]), tonumber(f[3])
        if mb == nil then return nil, '書式は measure,開始Beat[,1小節の拍数]' end
        if beats ~= nil and beats <= 0 then return nil, '1小節の拍数が0以下' end
        return { kind = 'measure', mb = mb, beats = beats or 4 }
    elseif kind == 'hs' then
        local g, v = tonumber(f[2]), tonumber(f[3])
        if g == nil or g < 0 or v == nil then
            return nil, '書式は hs,グループ,倍率（倍率は 0.1〜10。1が既定）'
        end
        if v < 0.1 or v > 10 then return nil, '倍率が範囲外（0.1〜10）' end
        return { kind = 'hs', g = math.floor(g), v = v }
    elseif kind == 'cam' then
        local b1, b2, ch, v1, v2 = toB(2), toB(3), f[4], toN(5), toN(6)
        if b1 == nil or b2 == nil or ch == nil or L3DCamRange[ch] == nil
            or v1 == nil or v2 == nil then
            return nil, '書式は cam,開始,終了,項目,開始値,終了値[,ease]（項目は angle/x/y/z/roll/zoom/rollpivot）'
        end
        if b2 < b1 then return nil, '終了が開始より前' end
        local r = L3DCamRange[ch]
        return { kind = 'cam', b1 = b1, b2 = b2, ch = ch,
                 v1 = L3DClamp(v1, r[1], r[2]), v2 = L3DClamp(v2, r[1], r[2]),
                 ease = toN(7) or 0 }
    end
    return nil, '未知のキーワード ' .. tostring(kind)
end

-- ソース(拍)を読む
local function L3DParseSrc(text)
    local list, errs = {}, {}
    local lines = L3DLines(text)
    for i = 1, #lines do
        local line = lines[i]
        if string.sub(line, 1, 2) == '#!' then
            local w = string.match(line, 'width=([%d%.]+)')
            local e = string.match(line, 'ease=(%d+)')
            local g = string.match(line, 'xgrid=(%w+)')
            if w ~= nil then L3DConfig.width = tonumber(w) end
            if e ~= nil then L3DConfig.ease = tonumber(e) end
            if g == 'auto' then
                L3DConfig.xgrid = -1
            elseif g ~= nil then
                L3DConfig.xgrid = tonumber(g) or -1
            end
        elseif string.sub(line, 1, 1) ~= '#' then
            local e, msg = L3DParseLine(L3DFields(line), true, nil)
            if e ~= nil then
                list[#list + 1] = e
            else
                errs[#errs + 1] = string.format('%d行目: %s', i, msg)
            end
        end
    end
    L3DSortElements(list)
    return list, errs
end

-- 既存の lane3d.ex(ms) を取り込む
local function L3DImportEx(text, timing)
    local list, errs = {}, {}
    local lines = L3DLines(text)
    for i = 1, #lines do
        local line = lines[i]
        if string.sub(line, 1, 1) ~= '#' then
            local e, msg = L3DParseLine(L3DFields(line), false, timing)
            if e ~= nil then
                list[#list + 1] = e
            else
                errs[#errs + 1] = string.format('%d行目: %s', i, msg)
            end
        end
    end
    L3DSortElements(list)
    return list, errs
end

local function L3DSerialize(list)
    local out = {}
    local gx = 'auto'
    if L3DConfig.xgrid ~= nil and L3DConfig.xgrid >= 0 then
        gx = string.format('%d', L3DConfig.xgrid)
    end
    out[#out + 1] = string.format('#!lane3d %s width=%s ease=%d xgrid=%s',
        L3D.Version, L3DNum(L3DConfig.width), L3DConfig.ease, gx)
    out[#out + 1] = '# ES3 プラグインのソース。時刻は拍。lane3d.ex はこれを書き出したもの'
    -- 呼び出し元の並びは変えない。並べ替えると選択中の要素の添字がずれる
    local sorted = {}
    for i = 1, #list do sorted[i] = list[i] end
    L3DSortElements(sorted)
    for i = 1, #sorted do
        local e = sorted[i]
        if e.kind == 'airtap' then
            out[#out + 1] = string.format('airtap,%s,%s,%s',
                L3DFormatBeat(e.b1), L3DNum(e.x1), L3DNum(e.w))
        elseif e.kind == 'airlift' then
            out[#out + 1] = string.format('airlift,%s,%s,%s,%s,%d,%s',
                L3DFormatBeat(e.b1), L3DFormatBeat(e.b2), L3DNum(e.x1), e.dir,
                e.ease or 0, L3DNum(e.w))
        elseif e.kind == 'airslide' then
            out[#out + 1] = string.format('airslide,%s,%s,%s,%s,%d,%s',
                L3DFormatBeat(e.b1), L3DFormatBeat(e.b2), L3DNum(e.x1), L3DNum(e.x2),
                e.ease or 0, L3DNum(e.w))
        elseif e.kind == 'measure' then
            out[#out + 1] = string.format('measure,%s,%s', L3DNum(e.mb), L3DNum(e.beats))
        elseif e.kind == 'hs' then
            out[#out + 1] = string.format('hs,%d,%s', e.g, L3DNum(e.v))
        elseif e.kind == 'cam' then
            out[#out + 1] = string.format('cam,%s,%s,%s,%s,%s,%d',
                L3DFormatBeat(e.b1), L3DFormatBeat(e.b2), e.ch,
                L3DNum(e.v1), L3DNum(e.v2), e.ease or 0)
        end
    end
    return table.concat(out, string.char(10))
end

-- ソースを読む。src -> 共有データ -> 既存の lane3d.ex の順に探す
local function L3DLoad()
    local text = L3DReadFileSafe(L3D.SrcFile)
    local from = L3D.SrcFile
    if text == nil then
        text = L3DReadData(L3D.DataKey)
        from = '共有データ'
    end
    if text ~= nil then
        local list, errs = L3DParseSrc(text)
        return list, from, errs
    end

    local ex = L3DReadFileSafe(L3D.ExFile)
    if ex ~= nil then
        local timing = L3DBuildTiming()
        local list, errs = L3DImportEx(ex, timing)
        return list, L3D.ExFile .. ' から取り込み', errs
    end
    return {}, '新規', {}
end

local function L3DSave(list)
    local text = L3DSerialize(list)
    local ok = L3DWriteFileSafe(L3D.SrcFile, text)
    L3DWriteData(L3D.DataKey, text)
    return ok, text
end

------------------------------------------------------------
-- Undo（Editor の Undo には乗らないので自前で持つ）
------------------------------------------------------------
local L3DUndoSep = string.char(10) .. '##UNDO##' .. string.char(10)

local function L3DUndoStack()
    local raw = L3DReadData(L3D.UndoKey)
    if raw == nil then return {} end
    local out = {}
    local pos = 1
    while true do
        local s, e = string.find(raw, L3DUndoSep, pos, true)
        if s == nil then
            out[#out + 1] = string.sub(raw, pos)
            break
        end
        out[#out + 1] = string.sub(raw, pos, s - 1)
        pos = e + 1
    end
    return out
end

local function L3DPushUndo(list)
    local stack = L3DUndoStack()
    stack[#stack + 1] = L3DSerialize(list)
    while #stack > L3D.UndoMax do table.remove(stack, 1) end
    L3DWriteData(L3D.UndoKey, table.concat(stack, L3DUndoSep))
end

local function L3DPopUndo()
    local stack = L3DUndoStack()
    if #stack == 0 then return nil end
    local text = table.remove(stack)
    L3DWriteData(L3D.UndoKey, table.concat(stack, L3DUndoSep))
    return text
end

------------------------------------------------------------
-- 規約チェック（仕様書 §6 の規約表が正）
--   却下 = その要素は使えない / 警告 = 遊びにくい可能性
------------------------------------------------------------
local function L3DCheck(list)
    local issues = {}
    local function add(level, e, msg)
        issues[#issues + 1] = { level = level, e = e, msg = msg }
    end

    for i = 1, #list do
        local e = list[i]
        if L3DIsBand(e) and not L3DIsInstant(e) then
            local dur = e.b2 - e.b1
            if dur < 0.125 then
                add('警告', e, string.format('1区間が 1/8 拍未満 (%.3f拍)', dur))
            end
            if e.kind == 'airlift' and dur < 0.25 then
                add('警告', e, string.format('Lift が 1/4 拍未満 (%.3f拍)', dur))
            end
            if e.kind == 'airslide' and dur > 0 then
                local lanes = (math.abs(e.x2 - e.x1) / L3D.LaneW) / dur
                if lanes > 2 then
                    add('警告', e, string.format('Slide が 1拍あたり %.1f レーン（目安は2まで）', lanes))
                end
            end
            if e.w == nil or e.w <= 0 then
                add('却下', e, '幅が0以下')
            end
        end
    end

    -- 繋ぎ目: 時刻が接しているのに位置が離れている
    for i = 1, #list do
        local e = list[i]
        if L3DIsBand(e) then
            local touching, matched = false, false
            for j = 1, #list do
                local p = list[j]
                if p ~= e and L3DIsBand(p) and math.abs(p.b2 - e.b1) <= 0.002 then
                    local px = L3DBandX(p, p.b2)
                    local ex = L3DBandX(e, e.b1)
                    if math.abs(px - ex) <= e.w then
                        touching = true
                        if math.abs(px - ex) < 20 then matched = true end
                    end
                end
            end
            if touching and not matched then
                add('警告', e, '直前の区間と位置がつながっていない')
            end
        end
    end

    -- E: 同時に3本以上
    for i = 1, #list do
        local e = list[i]
        if L3DIsBand(e) then
            local overlap = 1
            for j = 1, #list do
                local p = list[j]
                if p ~= e and L3DIsBand(p) and p.b1 < e.b2 and e.b1 < p.b2 then
                    overlap = overlap + 1
                end
            end
            if overlap > 2 then
                add('警告', e, string.format('同時に %d 本の AirSlide が重なっている（目安は2本まで）', overlap))
            end
        end
    end

    -- D: AirTap を帯の途中に重ねない
    for i = 1, #list do
        local e = list[i]
        if e.kind == 'airtap' then
            for j = 1, #list do
                local p = list[j]
                if L3DIsBand(p) and e.b1 > p.b1 + 0.002 and e.b1 < p.b2 - 0.002 then
                    if math.abs(L3DBandX(p, e.b1) - e.x1) < 20 then
                        add('却下', e, 'AirTap が AirSlide の途中に重なっている（端点か継ぎ目に置く）')
                        break
                    end
                end
            end
        end
    end

    -- measure は1つだけ
    local mcount = 0
    for i = 1, #list do
        if list[i].kind == 'measure' then mcount = mcount + 1 end
    end
    if mcount > 1 then
        add('警告', nil, string.format('measure が %d 行ある（効くのは最後の1行だけ）', mcount))
    end

    return issues
end

local function L3DBadSet(issues)
    local bad = {}
    for i = 1, #issues do
        if issues[i].e ~= nil then bad[issues[i].e] = issues[i].level end
    end
    return bad
end

------------------------------------------------------------
-- 書き出し（lane3d.ex）
------------------------------------------------------------
local function L3DExport()
    local list, from, errs = L3DLoad()
    if #list == 0 then
        Editor:ShowMessage('書き出すものがありません (' .. from .. ')')
        return false
    end

    local timing = L3DBuildTiming()
    local sorted = {}
    for i = 1, #list do sorted[i] = list[i] end
    L3DSortElements(sorted)

    local out = {}
    out[#out + 1] = '# Generated by ES3 plugin ' .. L3D.Version .. ' - do not edit by hand'
    out[#out + 1] = '# source: ' .. L3D.SrcFile
    for i = 1, #sorted do
        local e = sorted[i]
        if e.kind == 'airtap' then
            out[#out + 1] = string.format('airtap,%d,%s,%s',
                math.floor(L3DBeatMs(timing, e.b1) + 0.5), L3DNum(e.x1), L3DNum(e.w))
        elseif e.kind == 'airlift' then
            out[#out + 1] = string.format('airlift,%d,%d,%s,%s,%d,%s',
                math.floor(L3DBeatMs(timing, e.b1) + 0.5),
                math.floor(L3DBeatMs(timing, e.b2) + 0.5),
                L3DNum(e.x1), e.dir, e.ease or 0, L3DNum(e.w))
        elseif e.kind == 'airslide' then
            out[#out + 1] = string.format('airslide,%d,%d,%s,%s,%d,%s',
                math.floor(L3DBeatMs(timing, e.b1) + 0.5),
                math.floor(L3DBeatMs(timing, e.b2) + 0.5),
                L3DNum(e.x1), L3DNum(e.x2), e.ease or 0, L3DNum(e.w))
        elseif e.kind == 'measure' then
            out[#out + 1] = string.format('measure,%s,%s', L3DNum(e.mb), L3DNum(e.beats))
        elseif e.kind == 'hs' then
            out[#out + 1] = string.format('hs,%d,%s', e.g, L3DNum(e.v))
        elseif e.kind == 'cam' then
            out[#out + 1] = string.format('cam,%d,%d,%s,%s,%s,%d',
                math.floor(L3DBeatMs(timing, e.b1) + 0.5),
                math.floor(L3DBeatMs(timing, e.b2) + 0.5),
                e.ch, L3DNum(e.v1), L3DNum(e.v2), e.ease or 0)
        end
    end

    local okWrite = L3DWriteFileSafe(L3D.ExFile, table.concat(out, string.char(10)))
    local issues = L3DCheck(list)
    local rejected, warned = 0, 0
    for i = 1, #issues do
        if issues[i].level == '却下' then rejected = rejected + 1 else warned = warned + 1 end
    end

    local msg = string.format('%s に %d 行 書き出しました', L3D.ExFile, #list)
    if not okWrite then
        msg = '書き出しに失敗しました（WriteFile が使えない）'
    end
    if not timing.calibrated then
        msg = msg .. ' / ノーツが無いので拍の原点を合わせられません'
    end
    if rejected > 0 or warned > 0 or #errs > 0 then
        msg = msg .. string.format(' / 却下=%d 警告=%d 書式エラー=%d', rejected, warned, #errs)
    end
    Editor:ShowMessage(msg)
    return okWrite
end
-- <<< LANE3D COMMON END

-- >>> LANE3D OVERLAY BEGIN
------------------------------------------------------------
-- オーバーレイ描画
--   Editor-Specific Module は X=画面幅の% / Beat=縦位置(中心) / Width=% /
--   Height=ユニット / HeightBeat=拍。Beat も X も「中心」を指す
------------------------------------------------------------
local L3DMods = {}

local function L3DPct(x)
    return 100 * x / 256
end

local function L3DSprite(name)
    local m = Editor:AddSprite(name, L3D.Img)
    if m ~= nil then L3DMods[#L3DMods + 1] = name end
    return m
end

local function L3DText(name, content)
    local m = Editor:AddText(name, content)
    if m ~= nil then L3DMods[#L3DMods + 1] = name end
    return m
end

local function L3DClearMods()
    for i = 1, #L3DMods do
        Editor:RemoveModule(L3DMods[i])
    end
    L3DMods = {}
end

local function L3DPaint(m, col, alpha)
    if m == nil then return end
    -- 同じ名前のモジュールは使い回されるので、前に回転を入れていたら戻しておく
    m.Rotate = 0
    m:SetColor(col[1], col[2], col[3])
    m.Alpha = alpha
end

-- 縦の帯（時刻の区間 × 一定の x）
local function L3DBar(name, x, w, p1, p2, col, alpha)
    local m = L3DSprite(name)
    if m == nil then return end
    m.X = L3DPct(x)
    m.Width = L3DPct(w)
    m.Beat = L3DPointToBeat((p1 + p2) * 0.5)
    m.HeightBeat = L3DPointToBeat(p2 - p1)
    L3DPaint(m, col, alpha)
end

-- 横に細い印
local function L3DDot(name, x, w, p, h, col, alpha)
    local m = L3DSprite(name)
    if m == nil then return end
    m.X = L3DPct(x)
    m.Width = L3DPct(w)
    m.Beat = L3DPointToBeat(p)
    m.Height = h
    L3DPaint(m, col, alpha)
end

------------------------------------------------------------
-- 要素を1つ描く
------------------------------------------------------------
local function L3DDrawElement(e, tag, alpha, col)
    if e.kind == 'airtap' then
        L3DDot(tag, e.x1, e.w, e.b1, 12, col, alpha)
    elseif e.kind == 'airlift' then
        if L3DIsInstant(e) then
            -- 直角。長さが無いので帯にならない。太めの印と、向きを示す細い印で出す
            L3DDot(tag .. 'i', e.x1, e.w, e.b1, 18, col, alpha)
            L3DDot(tag .. 'c', e.x1, e.w * 0.45, e.b1, 30, L3DColor.cap, alpha)
        else
            L3DBar(tag .. 'b', e.x1, L3D.BodyW, e.b1, e.b2, col, alpha)
            -- 幅は両端だけで見せる。空中側の端は明るく（up は終わり、down は始まりが空中判定線）
            local skyP, floorP = e.b2, e.b1
            if e.dir == 'down' then skyP, floorP = e.b1, e.b2 end
            L3DDot(tag .. 'f', e.x1, e.w, floorP, 10, col, math.floor(alpha * 0.8))
            L3DDot(tag .. 'c', e.x1, e.w, skyP, 10, L3DColor.cap, alpha)
        end
    elseif e.kind == 'airslide' then
        -- 斜めの帯を「回転させた矩形」で引くと、角度を出すのに HeightBeat -> Height の
        -- 読み返しが要る。この読み返しが当てにならず、実機でオーバーレイが扇状に崩れた
        -- （2026-09-20）。回転も読み返しも使わず、区間を刻んで軸に沿った帯を並べる。
        -- 階段状になるが、幅と曲がり方はそのまま見える
        local n = 8
        if math.abs(e.x2 - e.x1) < 2 then n = 1 end   -- その場の帯は1枚で足りる
        for k = 1, n do
            local q0 = e.b1 + (e.b2 - e.b1) * ((k - 1) / n)
            local q1 = e.b1 + (e.b2 - e.b1) * (k / n)
            local mx = L3DBandX(e, (q0 + q1) * 0.5)
            L3DBar(tag .. 'l' .. k, mx, L3D.BodyW, q0, q1, col, alpha)
        end
        -- 幅は頭と尻尾だけで見せる。ここが幅を掴む場所でもある
        L3DDot(tag .. 'a', e.x1, e.w, e.b1, 10, col, math.floor(alpha * 0.8))
        L3DDot(tag .. 'z', e.x2, e.w, e.b2, 10, col, alpha)
    elseif e.kind == 'cam' then
        -- トラックの左脇に細い帯で置く。中身の編集は lane3d.src を直接
        local m = L3DSprite(tag .. 'c')
        if m ~= nil then
            m.X = -6
            m.Width = 2
            m.Beat = L3DPointToBeat((e.b1 + e.b2) * 0.5)
            m.HeightBeat = L3DPointToBeat(math.max(e.b2 - e.b1, 0.05))
            L3DPaint(m, L3DColor.cam, alpha)
        end
        local t = L3DText(tag .. 't', e.ch)
        if t ~= nil then
            t.X = -11
            t.Beat = L3DPointToBeat(e.b1)
            t.Alpha = alpha
        end
    end
end

local function L3DElementColor(e)
    if e.kind == 'airtap' then return L3DColor.tap end
    if e.kind == 'airlift' then
        if e.dir == 'down' then return L3DColor.down end
        return L3DColor.up
    end
    if e.kind == 'airslide' then return L3DColor.slide end
    return L3DColor.cam
end

------------------------------------------------------------
-- 全部描き直す
------------------------------------------------------------
local function L3DRedraw(list, selected, issues)
    L3DClearMods()
    local bad = L3DBadSet(issues or {})
    for i = 1, #list do
        local e = list[i]
        local col = L3DElementColor(e)
        local alpha = 75
        if bad[e] == '却下' then
            col, alpha = L3DColor.bad, 90
        elseif bad[e] == '警告' then
            alpha = 90
        end
        if i == selected then
            col, alpha = L3DColor.sel, 100
        end
        L3DDrawElement(e, 'l3d-e' .. i, alpha, col)
    end
end

------------------------------------------------------------
-- 当たり判定（拍と x の距離。1レーン ≒ 1拍として測る）
------------------------------------------------------------
local function L3DDistance(e, x, p)
    if e.kind == 'airtap' then
        return math.abs(p - e.b1) + math.abs(x - e.x1) / L3D.LaneW
    elseif L3DIsBand(e) then
        local q = L3DClamp(p, e.b1, e.b2)
        return math.abs(p - q) + math.abs(x - L3DBandX(e, q)) / L3D.LaneW
    end
    return 9999
end

local function L3DPickNearest(list, x, p, limit)
    local best, bestIdx = limit or 0.6, nil
    for i = 1, #list do
        local d = L3DDistance(list[i], x, p)
        if d < best then best, bestIdx = d, i end
    end
    return bestIdx
end

------------------------------------------------------------
-- 繋ぎ目スナップ。近くに他の要素の端があればそこへ寄せる
------------------------------------------------------------
local function L3DSnap(list, x, p, skipIdx)
    local bx, bp, best = x, p, 9999
    for i = 1, #list do
        if i ~= skipIdx then
            local e = list[i]
            local cand = {}
            if e.kind == 'airtap' then
                cand[1] = { e.x1, e.b1 }
            elseif L3DIsBand(e) then
                cand[1] = { L3DBandX(e, e.b1), e.b1 }
                cand[2] = { L3DBandX(e, e.b2), e.b2 }
            end
            for k = 1, #cand do
                local dx = math.abs(cand[k][1] - x)
                local dp = math.abs(cand[k][2] - p)
                if dx <= L3D.SnapX and dp <= L3D.SnapBeat then
                    local d = dx / L3D.LaneW + dp
                    if d < best then
                        best, bx, bp = d, cand[k][1], cand[k][2]
                    end
                end
            end
        end
    end
    return bx, bp
end
-- <<< LANE3D OVERLAY END

------------------------------------------------------------
-- 状態
------------------------------------------------------------
local Elements = {}
local Issues = {}
local Selected = nil
local Grab = nil            -- { mode = 'b1'|'b2'|'move', ox, op, orig }

local SaveFailed = false

local function Refresh(save)
    if save then
        local ok = L3DSave(Elements)
        if not ok and not SaveFailed then
            SaveFailed = true
            Editor:ShowMessage('lane3d.src に書けません（WriteFile が使えない）。共有データにだけ残ります')
        end
    end
    Issues = L3DCheck(Elements)
    L3DRedraw(Elements, Selected, Issues)
end

local function Describe(e)
    if e == nil then return 'ES3 Edit: 要素をタップして選ぶ' end
    if e.kind == 'airtap' then
        return string.format('AirTap %s x=%s 幅%s',
            L3DFormatBeat(e.b1), L3DNum(e.x1), L3DNum(e.w))
    elseif e.kind == 'airlift' then
        return string.format('AirLift %s %s %.3f拍 x=%s 幅%s',
            e.dir, L3DFormatBeat(e.b1), e.b2 - e.b1, L3DNum(e.x1), L3DNum(e.w))
    elseif e.kind == 'airslide' then
        return string.format('AirSlide %s %.3f拍 x=%s->%s 幅%s',
            L3DFormatBeat(e.b1), e.b2 - e.b1, L3DNum(e.x1), L3DNum(e.x2), L3DNum(e.w))
    end
    return e.kind
end

local function Tip()
    local e = nil
    if Selected ~= nil then e = Elements[Selected] end
    local msg = Describe(e)
    if e ~= nil then
        for i = 1, #Issues do
            if Issues[i].e == e then
                msg = msg .. ' / ' .. Issues[i].level .. ': ' .. Issues[i].msg
                break
            end
        end
        if Grab ~= nil then
            local how = '全体を移動'
            if Grab.mode == 'b1' or Grab.mode == 'b2' then
                how = '時刻'
            elseif Grab.mode == 'wid' then
                how = '幅'
            end
            msg = msg .. ' / ' .. how
        else
            msg = msg .. ' / 端をドラッグで時刻・左右の端で幅 / もう一度タップで削除'
        end
    end
    Editor:ShowTip(msg)
end

-- Edit は**生の横位置**で当たりを見る。スナップした値だと列の中心に吸われて
-- 「端を掴む」ができない。動かした結果のほうは ApplyGrab でグリッドに載せ直す
local function ClickPos()
    return L3DClickRaw()
end

local function CopyElement(e)
    local c = {}
    for k, v in pairs(e) do c[k] = v end
    return c
end

------------------------------------------------------------
-- プラグイン起動時 / 終了時
------------------------------------------------------------
function OnActive()
    local from
    Elements, from = L3DLoad()
    L3DPrepareGrid()
    Selected = nil
    Grab = nil
    Refresh(false)
    Tip()
    Editor:ShowMessage(string.format('ES3 Edit: %d要素 (%s) / 横グリッド %s',
        #Elements, from, L3DGridLabel()))
end

function OnDeactive()
    L3DClearMods()
    Editor:ShowTip('')
    Selected = nil
    Grab = nil
end

------------------------------------------------------------
-- タップ: 選ぶ / 消す
------------------------------------------------------------
function OnClick()
    local x, p = ClickPos()
    if x == nil then return end
    local idx = L3DPickNearest(Elements, x, p, 0.6)
    if idx == nil then
        Selected = nil
        Refresh(false)
        Tip()
        return
    end
    if Selected == idx then
        L3DPushUndo(Elements)
        table.remove(Elements, idx)
        Selected = nil
        Refresh(true)
        Editor:ShowTip('削除しました')
        return
    end
    Selected = idx
    Refresh(false)
    Tip()
end

------------------------------------------------------------
-- ドラッグ: 端を掴んで動かす / 全体を動かす
------------------------------------------------------------
function OnDragStart()
    local x, p = ClickPos()
    if x == nil then
        Grab = nil
        return
    end
    local idx = Selected
    if idx == nil then
        idx = L3DPickNearest(Elements, x, p, 0.6)
        Selected = idx
    end
    if idx == nil then
        Grab = nil
        return
    end

    local e = Elements[idx]
    local mode = 'move'

    -- 見た目に合わせて掴み分ける。
    --   細い芯の中  -> 端の近くなら時刻、真ん中なら移動
    --   芯の外（頭と尻尾で幅を見せている部分）-> 幅
    local cx = L3DElemX(e, p)
    local off = math.abs(x - cx)
    local half = (e.w or L3DConfig.width) * 0.5
    local coreHalf = L3D.BodyW * 0.5
    -- 幅が芯と同じくらい細い要素でも広げられるよう、外側に少し余裕を持たせる
    local onFlank = off > coreHalf and off <= half + 14

    if off <= coreHalf and L3DIsBand(e) and not L3DIsInstant(e) then
        -- 直角の Lift は長さが無く、どこを掴んでも「端」になってしまうので端モードに入れない
        local d1 = math.abs(p - e.b1)
        local d2 = math.abs(p - e.b2)
        if d1 <= d2 and d1 < 0.35 then
            mode = 'b1'
        elseif d2 < d1 and d2 < 0.35 then
            mode = 'b2'
        end
    elseif onFlank then
        mode = 'wid'
    end
    Grab = { mode = mode, ox = x, op = p, orig = CopyElement(e) }
    Refresh(false)
    Tip()
end

local function ApplyGrab(x, p)
    if Grab == nil or Selected == nil then return end
    local o = Grab.orig
    local e = Elements[Selected]
    local dx = x - Grab.ox
    local dp = p - Grab.op
    local minLen = 1 / L3D.Denom

    -- 端で止めたときにグリッドから外れないよう、結果をもう一度載せ直す
    local function px(v) return L3DSnapX(L3DClamp(v, 0, 255)) end
    local function pb(v) return L3DSnapBeat(v) end

    if Grab.mode == 'move' then
        if o.kind == 'airtap' then
            e.b1 = pb(o.b1 + dp)
            e.x1 = px(o.x1 + dx)
        else
            e.b1 = pb(o.b1 + dp)
            e.b2 = pb(o.b2 + dp)
            e.x1 = px(o.x1 + dx)
            if o.kind == 'airslide' then
                e.x2 = px(o.x2 + dx)
            end
        end
    elseif Grab.mode == 'b1' then
        -- Lift は x が固定なので、どちらの端を掴んでも x1 が動く
        e.b1 = math.min(pb(o.b1 + dp), o.b2 - minLen)
        e.x1 = px(o.x1 + dx)
    elseif Grab.mode == 'b2' then
        e.b2 = math.max(pb(o.b2 + dp), o.b1 + minLen)
        if o.kind == 'airslide' then
            e.x2 = px(o.x2 + dx)
        else
            e.x1 = px(o.x1 + dx)
        end
    elseif Grab.mode == 'wid' then
        -- 掴んだ時刻での中心は動かさず、そこから指までの距離の2倍を幅にする。
        -- 中心を固定するほうが、幅だけ変えたいときに位置がずれなくて済む
        local cx = L3DElemX(o, Grab.op)
        e.w = L3DSnapWidth(math.abs(x - cx) * 2)
    end
end

function OnDragMove()
    if Grab == nil then return end
    local x, p = ClickPos()
    if x == nil then return end
    ApplyGrab(x, p)
    L3DRedraw(Elements, Selected, Issues)
    Tip()
end

function OnDragEnd()
    if Grab == nil then return end
    local x, p = ClickPos()
    if x ~= nil then
        local sx, sp = L3DSnap(Elements, x, p, Selected)
        ApplyGrab(sx, sp)
    end
    -- 動かす前の姿を Undo に積む
    local before = {}
    for i = 1, #Elements do
        if i == Selected then
            before[i] = Grab.orig
        else
            before[i] = Elements[i]
        end
    end
    L3DPushUndo(before)
    Grab = nil
    Refresh(true)
    Tip()
end

------------------------------------------------------------
-- キーボードの近道（PC のみ）
--   Delete 削除 / Z 1手戻す / S 書き出し
------------------------------------------------------------
function OnKey(key, down)
    if not down then return end
    if key == 127 or key == 46 then
        if Selected == nil then return end
        L3DPushUndo(Elements)
        table.remove(Elements, Selected)
        Selected = nil
        Refresh(true)
    elseif key == 122 or key == 90 then
        local text = L3DPopUndo()
        if text == nil then
            Editor:ShowTip('戻せる操作がありません')
            return
        end
        Elements = L3DParseSrc(text)
        Selected = nil
        Refresh(true)
    elseif key == 115 or key == 83 then
        L3DExport()
    end
    Tip()
end
