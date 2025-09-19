-- =========================================================
-- Author: Physic
-- Version: 1.0.0
-- LastEditTime: 2025-09-19
-- =========================================================

------------------------------------------------------------
-- プラグイン情報
------------------------------------------------------------
PluginName = 'img2wipe'
PluginMode = 7
PluginType = 0
PluginRequire = '6.5.12'

local NoteType = {
    Tap = 1,
    Wipe = 1024,
    Slide = 2048
}

local ImageType = {
    BMP = 1,
    PNG = 2,
    JPG = 3,
    Other = 99
}


function Run()
    Editor:ReadBytesSelect('Please select your image',
        function(value)
            local ext = GetFormat(value)
            local bwMap = {}
            if ext == false then
                Editor:ShowMessage('No file selected.')
                return
            elseif ext == ImageType.BMP then
                bwMap = BmpToBwPixel(value)
            elseif ext == ImageType.PNG then
                Editor:ShowMessage('Unsupported file type (png). Please select a BMP file.')
                return
            elseif ext == ImageType.JPG then
                Editor:ShowMessage('Unsupported file type (jpg). Please select a BMP file.')
                return
            elseif ext == ImageType.Other then
                Editor:ShowMessage('Unsupported file type. Please select a BMP file.')
                return
            end
            BwPixelToWipe(bwMap)
        end
    )
end

------------------------------------------------------------
-- BMP から 64 × 64 の白黒2次元配列に変換
------------------------------------------------------------
function BmpToBwPixel(array)
    -- ヘッダー情報の抽出
    local function le_bytes(start, len)
        local n = 0
        for i = 0, len - 1 do
            n = n + array[start + i] * (256 ^ i)
        end
        return n
    end
    local width = le_bytes(18, 4)
    local height = le_bytes(22, 4)
    local row_padded = math.ceil(width * 3 / 4) * 4

    -- ピクセル配列抽出
    local pixels = {}
    local base = 54
    for y = height, 1, -1 do
        local row_start = base + (height - y) * row_padded
        for x = 0, width - 1 do
            local idx = row_start + x * 3
            local b, g, r = array[idx], array[idx + 1], array[idx + 2]
            table.insert(pixels, r)
            table.insert(pixels, g)
            table.insert(pixels, b)
        end
    end

    -- 最近傍法で64x64リサイズ、白黒化
    local bw = {}
    for y = 1, 64 do
        local sy = math.floor((y - 1) * height / 64)
        for x = 1, 64 do
            local sx = math.floor((x - 1) * width / 64)
            local idx = (sy * width + sx) * 3 + 1
            local r, g, b = pixels[idx], pixels[idx + 1], pixels[idx + 2]

            -- RGBからグレースケール値に変換
            local y_val = 0.299 * r + 0.587 * g + 0.114 * b
            if not bw[y] then bw[y] = {} end
            if y_val > 128 then
                bw[y][x] = 1 -- 白
            else
                bw[y][x] = 0 -- 黒
                local headNote = Editor:AddNote(NoteType.Wipe)
                Editor:SetNoteBeat(headNote, Editor:BeatAdd(Editor:GetCurrentBeat(), Editor:MakeBeat(0, y, 64)), true)
                Editor:SetNoteX(headNote, x * 4)
                Editor:SetNoteWidth(headNote, 1)
            end
        end
    end
    return bw
end

------------------------------------------------------------
-- BMP から 64 × 64 の白黒2次元配列に変換
------------------------------------------------------------
function PngToBwPixel(array)
    -- PNG処理は未実装
end

------------------------------------------------------------
-- JPG から 64 × 64 の白黒2次元配列に変換
------------------------------------------------------------
function JpgToBwPixel(array)
    -- JPG処理は未実装
end

------------------------------------------------------------
-- 白黒2次元配列から Wipe を生成
------------------------------------------------------------
function BwPixelToWipe(bw)
    for y = 1, 64 do
        for x = 1, 64 do
            if bw[y][x] == 0 then
                local headNote = Editor:AddNote(NoteType.Wipe)
                Editor:SetNoteBeat(headNote, Editor:BeatAdd(Editor:GetCurrentBeat(), Editor:MakeBeat(0, y, 64)), true)
                Editor:SetNoteX(headNote, x * 4)
                Editor:SetNoteWidth(headNote, 1)
            end
        end
    end
end

------------------------------------------------------------
-- 拡張子判定
------------------------------------------------------------
function GetFormat(array)
    if array == nil then return false end

    -- BMP: 先頭2バイトが "BM" (0x42, 0x4D)
    if array[0] == 0x42 and array[1] == 0x4D then
        return ImageType.BMP
    end

    -- PNG: 先頭8バイトが 89 50 4E 47 0D 0A 1A 0A
    if array[0] == 0x89 and array[1] == 0x50 and array[2] == 0x4E and array[3] == 0x47
        and array[4] == 0x0D and array[5] == 0x0A and array[6] == 0x1A and array[7] == 0x0A then
        return ImageType.PNG
    end

    -- JPEG: 先頭2バイトが 0xFF 0xD8、末尾2バイトが 0xFF 0xD9
    if array[0] == 0xFF and array[1] == 0xD8 then
        return ImageType.JPG
    end

    return ImageType.Other
end