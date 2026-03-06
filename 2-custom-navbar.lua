-- Bottom Navigation Bar patch for KOReader File Manager
-- Adds a tab bar at the bottom with Books, Manga, News, Continue
-- Sits below pagination controls

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileManager = require("apps/filemanager/filemanager")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")

-- === Layout constants ===

local navbar_icon_size = Screen:scaleBySize(34)
local navbar_font = Font:getFace("smallinfofont")
local navbar_font_bold = Font:getFace("smallinfofontbold")
local navbar_v_padding = Screen:scaleBySize(4)
local navbar_top_gap = Screen:scaleBySize(10)
local underline_thickness = Screen:scaleBySize(2)

-- === Persistent config ===

local config_default = {
    show_tabs = {
        books = true,
        manga = true,
        news = true,
        continue = true,
        history = false,
        favorites = false,
        collections = false,
    },
    tab_order = { "books", "manga", "news", "continue", "history", "favorites", "collections" },
    show_labels = true,
    show_top_border = true,
    books_label = "Books",
    manga_action = "rakuyomi",
    manga_folder = "",
    news_action = "quickrss",
    news_folder = "",
    colored = false,
    active_tab_color = {0x33, 0x99, 0xFF}, -- blue
}

local function loadConfig()
    local config = G_reader_settings:readSetting("bottom_navbar", config_default)
    for k, v in pairs(config_default) do
        if config[k] == nil then
            config[k] = v
        end
    end
    if type(config.show_tabs) == "table" then
        for k, v in pairs(config_default.show_tabs) do
            if config.show_tabs[k] == nil then
                config.show_tabs[k] = v
            end
        end
    else
        config.show_tabs = config_default.show_tabs
    end
    -- Ensure tab_order contains all known tabs
    if type(config.tab_order) ~= "table" then
        config.tab_order = config_default.tab_order
    else
        local order_set = {}
        for _, v in ipairs(config.tab_order) do order_set[v] = true end
        for _, v in ipairs(config_default.tab_order) do
            if not order_set[v] then
                table.insert(config.tab_order, v)
            end
        end
    end
    return config
end

local config = loadConfig()

-- === Tab definitions ===

local function getBooksLabel()
    return config.books_label ~= "" and config.books_label or "Books"
end

local tabs = {
    {
        id = "books",
        label = getBooksLabel(),
        icon = "book.opened",
    },
    {
        id = "manga",
        label = _("Manga"),
        icon = "tab_manga",
    },
    {
        id = "news",
        label = _("News"),
        icon = "tab_news",
    },
    {
        id = "continue",
        label = _("Continue"),
        icon = "tab_continue",
    },
    {
        id = "history",
        label = _("History"),
        icon = "tab_history",
    },
    {
        id = "favorites",
        label = _("Favorites"),
        icon = "star.full",
    },
    {
        id = "collections",
        label = _("Collections"),
        icon = "tab_collections",
    },
}

local tabs_by_id = {}
for _, tab in ipairs(tabs) do
    tabs_by_id[tab.id] = tab
end

-- === Active tab tracking ===

local active_tab = "books"

-- Forward declaration; defined later
local injectNavbar

local function setActiveTab(id)
    active_tab = id
    local fm = FileManager.instance
    if fm then
        injectNavbar(fm)
        UIManager:setDirty(fm, "ui")
    end
end

-- === Tab callbacks ===

local function onTabBooks()
    local fm = FileManager.instance
    if not fm then return end
    local home_dir = G_reader_settings:readSetting("home_dir")
                     or require("apps/filemanager/filemanagerutil").getDefaultDir()
    fm.file_chooser.path_items[home_dir] = nil
    fm.file_chooser:changeToPath(home_dir)
end

local function onTabManga()
    local fm = FileManager.instance
    if not fm then return end

    if config.manga_action == "folder" and config.manga_folder ~= "" then
        if lfs.attributes(config.manga_folder, "mode") == "directory" then
            fm.file_chooser:changeToPath(config.manga_folder)
        else
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("Manga folder not found: ") .. config.manga_folder,
            })
        end
        return
    end

    -- Default: open Rakuyomi
    local rakuyomi = fm.rakuyomi
    if rakuyomi then
        rakuyomi:openLibraryView()
    else
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _("Rakuyomi plugin is not installed."),
        })
    end
end

local function onTabNews()
    local fm = FileManager.instance
    if not fm then return end

    if config.news_action == "folder" and config.news_folder ~= "" then
        if lfs.attributes(config.news_folder, "mode") == "directory" then
            fm.file_chooser:changeToPath(config.news_folder)
        else
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("News folder not found: ") .. config.news_folder,
            })
        end
        return
    end

    -- Default: open QuickRSS
    local ok, QuickRSSUI = pcall(require, "modules/ui/feed_view")
    if ok and QuickRSSUI then
        UIManager:show(QuickRSSUI:new{})
    else
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _("QuickRSS plugin is not installed."),
        })
    end
end

local function onTabContinue()
    local last_file = G_reader_settings:readSetting("lastfile")
    if not last_file or lfs.attributes(last_file, "mode") ~= "file" then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _("Cannot open last document"),
        })
        return
    end
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(last_file)
end

local function onTabHistory()
    local fm = FileManager.instance
    if fm and fm.history then
        fm.history:onShowHist()
    end
end

local function onTabFavorites()
    local fm = FileManager.instance
    if fm and fm.collections then
        fm.collections:onShowColl()
    end
end

local function onTabCollections()
    local fm = FileManager.instance
    if fm and fm.collections then
        fm.collections:onShowCollList()
    end
end

local tab_callbacks = {
    books = onTabBooks,
    manga = onTabManga,
    news = onTabNews,
    continue = onTabContinue,
    history = onTabHistory,
    favorites = onTabFavorites,
    collections = onTabCollections,
}

-- === Color text support ===
-- TextWidget uses colorblitFrom which converts RGB to grayscale.
-- We need colorblitFromRGB32 for actual color rendering.

local RenderText = require("ui/rendertext")

local ColorTextWidget = TextWidget:extend{}

function ColorTextWidget:paintTo(bb, x, y)
    self:updateSize()
    if self._is_empty then return end

    if not self.fgcolor or Blitbuffer.isColor8(self.fgcolor) or not Screen:isColorScreen() then
        TextWidget.paintTo(self, bb, x, y)
        return
    end

    if not self.use_xtext then
        TextWidget.paintTo(self, bb, x, y)
        return
    end

    if not self._xshaping then
        self._xshaping = self._xtext:shapeLine(self._shape_start, self._shape_end,
                                            self._shape_idx_to_substitute_with_ellipsis)
    end

    local text_width = bb:getWidth() - x
    if self.max_width and self.max_width < text_width then
        text_width = self.max_width
    end
    local pen_x = 0
    local baseline = self.forced_baseline or self._baseline_h
    for _, xglyph in ipairs(self._xshaping) do
        if pen_x >= text_width then break end
        local face = self.face.getFallbackFont(xglyph.font_num)
        local glyph = RenderText:getGlyphByIndex(face, xglyph.glyph, self.bold)
        bb:colorblitFromRGB32(
            glyph.bb,
            x + pen_x + glyph.l + xglyph.x_offset,
            y + baseline - glyph.t - xglyph.y_offset,
            0, 0,
            glyph.bb:getWidth(), glyph.bb:getHeight(),
            self.fgcolor)
        pen_x = pen_x + xglyph.x_advance
    end
end

-- === Colored icon widget ===
-- Flattened icons are black-on-white, but colorblitFromRGB32 treats bright
-- pixels as full coverage. We invert the bitmap so the icon shape (now white)
-- gets full color and the background (now black) gets none, then restore it.

local ColorIconWidget = IconWidget:extend{
    _tint_color = nil,
}

function ColorIconWidget:paintTo(bb, x, y)
    if not self._tint_color or not Screen:isColorScreen() then
        IconWidget.paintTo(self, bb, x, y)
        return
    end

    if self.hide then return end
    local size = self:getSize()
    if not self.dimen then
        self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    else
        self.dimen.x = x
        self.dimen.y = y
    end
    self._bb:invert()
    bb:colorblitFromRGB32(
        self._bb, x, y,
        self._offset_x, self._offset_y,
        size.w, size.h,
        self._tint_color)
    self._bb:invert()
end

-- === Build a single tab (visual only) ===

local function createTabWidget(tab, tab_w, is_active)
    local use_color = config.colored and is_active and Screen:isColorScreen()
    local active_color
    if use_color then
        local c = config.active_tab_color
        if c and type(c) == "table" then
            active_color = Blitbuffer.ColorRGB32(c[1], c[2], c[3], 0xFF)
        end
    end

    local icon
    if active_color then
        icon = ColorIconWidget:new{
            icon = tab.icon,
            width = navbar_icon_size,
            height = navbar_icon_size,
            _tint_color = active_color,
        }
    else
        icon = IconWidget:new{
            icon = tab.icon,
            width = navbar_icon_size,
            height = navbar_icon_size,
        }
    end

    local label
    if active_color then
        label = ColorTextWidget:new{
            text = tab.label,
            face = navbar_font_bold,
            fgcolor = active_color,
        }
    else
        label = TextWidget:new{
            text = tab.label,
            face = is_active and navbar_font_bold or navbar_font,
        }
    end

    local icon_label_group
    if config.show_labels then
        icon_label_group = VerticalGroup:new{
            align = "center",
            icon,
            label,
        }
    else
        icon_label_group = VerticalGroup:new{
            align = "center",
            icon,
        }
    end

    local underline
    if is_active then
        local underline_color = Blitbuffer.COLOR_BLACK
        if config.colored then
            local c = config.active_tab_color
            if c and type(c) == "table" then
                underline_color = Blitbuffer.ColorRGB32(c[1], c[2], c[3], 0xFF)
            end
        end
        if config.colored and Screen:isColorScreen() then
            -- LineWidget uses paintRect which converts to grayscale.
            -- Use a custom widget with paintRectRGB32 for color.
            local Widget = require("ui/widget/widget")
            local color_line = Widget:new{
                dimen = Geom:new{ w = tab_w, h = underline_thickness },
            }
            function color_line:paintTo(bb, x, y)
                bb:paintRectRGB32(x, y, self.dimen.w, self.dimen.h, underline_color)
            end
            underline = color_line
        else
            underline = LineWidget:new{
                dimen = Geom:new{ w = tab_w, h = underline_thickness },
                background = underline_color,
            }
        end
    else
        underline = VerticalSpan:new{ width = underline_thickness }
    end

    local v_pad = config.show_labels and navbar_v_padding or navbar_v_padding * 2

    return CenterContainer:new{
        dimen = Geom:new{ w = tab_w, h = icon_label_group:getSize().h + v_pad * 2 + underline_thickness },
        VerticalGroup:new{
            align = "center",
            underline,
            VerticalSpan:new{ width = v_pad },
            icon_label_group,
            VerticalSpan:new{ width = v_pad },
        },
    }
end

-- === Build the full navbar ===

local HorizontalSpan = require("ui/widget/horizontalspan")
local navbar_h_padding = Screen:scaleBySize(10)

local function getVisibleTabs()
    local visible = {}
    for _, id in ipairs(config.tab_order) do
        if (id == "books" or config.show_tabs[id]) and tabs_by_id[id] then
            table.insert(visible, tabs_by_id[id])
        end
    end
    return visible
end

local function createNavBar()
    -- Update books tab label from config
    tabs_by_id["books"].label = getBooksLabel()

    local visible_tabs = getVisibleTabs()
    if #visible_tabs == 0 then return nil end

    local screen_w = Screen:getWidth()
    local inner_w = screen_w - navbar_h_padding * 2
    local tab_w = math.floor(inner_w / #visible_tabs)

    local row = HorizontalGroup:new{}
    for _, tab in ipairs(visible_tabs) do
        table.insert(row, createTabWidget(tab, tab_w, tab.id == active_tab))
    end

    local OverlapGroup = require("ui/widget/overlapgroup")
    local row_with_padding = HorizontalGroup:new{
        HorizontalSpan:new{ width = navbar_h_padding },
        row,
        HorizontalSpan:new{ width = navbar_h_padding },
    }
    local row_h = row_with_padding:getSize().h

    local visual_children = {}

    if config.show_top_border then
        local separator = LineWidget:new{
            dimen = Geom:new{ w = inner_w, h = Size.line.medium },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        }
        -- OverlapGroup: gray separator behind, tab row (with underlines) on top
        local separator_and_row = OverlapGroup:new{
            dimen = Geom:new{ w = screen_w, h = row_h },
            allow_mirroring = false,
            CenterContainer:new{
                dimen = Geom:new{ w = screen_w, h = Size.line.medium },
                separator,
            },
            row_with_padding,
        }
        table.insert(visual_children, VerticalSpan:new{ width = navbar_top_gap })
        table.insert(visual_children, separator_and_row)
    else
        table.insert(visual_children, VerticalSpan:new{ width = navbar_top_gap })
        table.insert(visual_children, row_with_padding)
    end

    local visual = VerticalGroup:new(visual_children)

    -- Wrap in InputContainer to handle taps on the whole navbar
    local navbar = InputContainer:new{
        dimen = Geom:new{ w = screen_w, h = visual:getSize().h },
        ges_events = {
            TapNavBar = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{ x = 0, y = 0, w = screen_w, h = Screen:getHeight() },
                },
            },
        },
    }

    navbar.onTapNavBar = function(self, _, ges)
        -- Only handle taps within the navbar's actual screen area
        if not self.dimen or not self.dimen:contains(ges.pos) then
            return false
        end
        -- Determine which tab was tapped based on x position
        local tap_x = ges.pos.x - navbar_h_padding
        local idx = math.floor(tap_x / tab_w) + 1
        idx = math.max(1, math.min(#visible_tabs, idx))
        local tapped_id = visible_tabs[idx].id
        local cb = tab_callbacks[tapped_id]
        if cb then cb() end
        -- Update active tab highlight for tabs that stay in file browser
        if tapped_id ~= active_tab then
            setActiveTab(tapped_id)
        end
        return true
    end

    navbar[1] = visual
    return navbar
end

-- === Hook Menu:init() to reduce FileChooser height ===

local Menu = require("ui/widget/menu")

local function getNavbarHeight()
    local nb = createNavBar()
    return nb and nb:getSize().h or 0
end

local orig_menu_init = Menu.init

function Menu:init()
    if self.name == "filemanager" and not self.height then
        self.height = Screen:getHeight() - getNavbarHeight()
    end
    orig_menu_init(self)
end

-- === Auto-switch active tab on folder change ===

local orig_onPathChanged = FileManager.onPathChanged

function FileManager:onPathChanged(path)
    if orig_onPathChanged then
        orig_onPathChanged(self, path)
    end

    local function startsWith(str, prefix)
        return str:sub(1, #prefix) == prefix
    end

    local new_tab
    -- Check manga folder
    if config.manga_action == "folder" and config.manga_folder ~= "" then
        if path == config.manga_folder or startsWith(path, config.manga_folder .. "/") then
            new_tab = "manga"
        end
    end
    -- Check news folder
    if not new_tab and config.news_action == "folder" and config.news_folder ~= "" then
        if path == config.news_folder or startsWith(path, config.news_folder .. "/") then
            new_tab = "news"
        end
    end
    -- Check home dir for books
    if not new_tab then
        local home_dir = G_reader_settings:readSetting("home_dir")
                         or require("apps/filemanager/filemanagerutil").getDefaultDir()
        if path == home_dir or startsWith(path, home_dir .. "/") then
            new_tab = "books"
        end
    end

    if new_tab and new_tab ~= active_tab then
        active_tab = new_tab
        injectNavbar(self)
        UIManager:setDirty(self, "ui")
    end
end

-- === Inject navbar INTO the existing fm_ui FrameContainer ===
-- Deferred to run AFTER all plugins (coverbrowser etc.) finish init

injectNavbar = function(fm)
    local fm_ui = fm[1]            -- FrameContainer wrapping file_chooser
    if not fm_ui then return end

    local file_chooser
    if fm._navbar_injected then
        -- Already injected: fm_ui[1] is VerticalGroup{file_chooser, navbar}
        file_chooser = fm_ui[1] and fm_ui[1][1]
    else
        file_chooser = fm_ui[1]    -- the actual FileChooser/MosaicMenu widget
    end
    if not file_chooser then return end

    fm._navbar_injected = true

    local navbar = createNavBar()
    if not navbar then
        fm_ui[1] = file_chooser
        return
    end

    -- Update FileChooser height to account for (potentially changed) navbar height
    local navbar_h = navbar:getSize().h
    local new_height = Screen:getHeight() - navbar_h
    if file_chooser.height ~= new_height then
        local chrome = file_chooser.dimen.h - file_chooser.inner_dimen.h
        file_chooser.height = new_height
        file_chooser.dimen.h = new_height
        file_chooser.inner_dimen.h = new_height - chrome
        file_chooser:updateItems()
    end

    fm_ui[1] = VerticalGroup:new{
        align = "left",
        file_chooser,
        navbar,
    }
end

local orig_setupLayout = FileManager.setupLayout

function FileManager:setupLayout()
    orig_setupLayout(self)

    -- On reinit, re-inject (preserve active tab)
    self._navbar_injected = false

    -- Defer injection to after all init processing completes
    local fm = self
    UIManager:nextTick(function()
        injectNavbar(fm)
        UIManager:setDirty(fm, "ui")
    end)
end

-- === Settings menu ===

local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")

local orig_setUpdateItemTable = FileManagerMenu.setUpdateItemTable

function FileManagerMenu:setUpdateItemTable()
    table.insert(FileManagerMenuOrder.filemanager_settings, "navbar_settings")

    self.menu_items.navbar_settings = {
        text = _("Navbar settings"),
        sub_item_table = {
            {
                text = _("Show labels"),
                checked_func = function() return config.show_labels end,
                callback = function()
                    config.show_labels = not config.show_labels
                    G_reader_settings:saveSetting("bottom_navbar", config)
                end,
            },
            {
                text = _("Show top border"),
                checked_func = function() return config.show_top_border end,
                callback = function()
                    config.show_top_border = not config.show_top_border
                    G_reader_settings:saveSetting("bottom_navbar", config)
                end,
            },
            {
                text = _("Colored active tab"),
                checked_func = function() return config.colored end,
                callback = function()
                    config.colored = not config.colored
                    G_reader_settings:saveSetting("bottom_navbar", config)
                end,
            },
            {
                text = _("Tabs"),
                sub_item_table = {
                    {
                        text = _("Arrange tabs"),
                        keep_menu_open = true,
                        callback = function()
                            local SortWidget = require("ui/widget/sortwidget")
                            local sort_items = {}
                            for _, id in ipairs(config.tab_order) do
                                local tab = tabs_by_id[id]
                                if tab then
                                    table.insert(sort_items, {
                                        text = tab.label,
                                        orig_item = id,
                                        dim = not config.show_tabs[id],
                                    })
                                end
                            end
                            UIManager:show(SortWidget:new{
                                title = _("Arrange navbar tabs"),
                                item_table = sort_items,
                                callback = function()
                                    for i, item in ipairs(sort_items) do
                                        config.tab_order[i] = item.orig_item
                                    end
                                    G_reader_settings:saveSetting("bottom_navbar", config)
                                end,
                            })
                        end,
                    },
                    {
                        text_func = function()
                            return _("Books tab label: ") .. getBooksLabel()
                        end,
                        separator = true,
                        sub_item_table = {
                            {
                                text = _("Books"),
                                checked_func = function() return config.books_label == "Books" or config.books_label == "" end,
                                callback = function()
                                    config.books_label = "Books"
                                    G_reader_settings:saveSetting("bottom_navbar", config)
                                end,
                            },
                            {
                                text = _("Home"),
                                checked_func = function() return config.books_label == "Home" end,
                                callback = function()
                                    config.books_label = "Home"
                                    G_reader_settings:saveSetting("bottom_navbar", config)
                                end,
                            },
                            {
                                text = _("Library"),
                                checked_func = function() return config.books_label == "Library" end,
                                callback = function()
                                    config.books_label = "Library"
                                    G_reader_settings:saveSetting("bottom_navbar", config)
                                end,
                            },
                            {
                                text_func = function()
                                    local presets = {[""] = true, Books = true, Home = true, Library = true}
                                    if presets[config.books_label] then
                                        return _("Custom")
                                    end
                                    return _("Custom: ") .. config.books_label
                                end,
                                checked_func = function()
                                    local presets = {[""] = true, Books = true, Home = true, Library = true}
                                    return not presets[config.books_label]
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    local InputDialog = require("ui/widget/inputdialog")
                                    local dlg
                                    dlg = InputDialog:new{
                                        title = _("Books tab label"),
                                        input = config.books_label,
                                        buttons = {{
                                            {
                                                text = _("Cancel"),
                                                id = "close",
                                                callback = function() UIManager:close(dlg) end,
                                            },
                                            {
                                                text = _("Set"),
                                                is_enter_default = true,
                                                callback = function()
                                                    local text = dlg:getInputText()
                                                    config.books_label = text ~= "" and text or "Books"
                                                    G_reader_settings:saveSetting("bottom_navbar", config)
                                                    UIManager:close(dlg)
                                                    if touchmenu_instance then
                                                        touchmenu_instance:updateItems()
                                                    end
                                                end,
                                            },
                                        }},
                                    }
                                    UIManager:show(dlg)
                                    dlg:onShowKeyboard()
                                end,
                            },
                        },
                    },
                    {
                        text = _("Manga"),
                        checked_func = function() return config.show_tabs.manga end,
                        callback = function()
                            config.show_tabs.manga = not config.show_tabs.manga
                            G_reader_settings:saveSetting("bottom_navbar", config)
                        end,
                    },
                    {
                        text_func = function()
                            if config.manga_action == "folder" then
                                return _("Manga tab action: ") .. _("Folder")
                            end
                            return _("Manga tab action: ") .. _("Rakuyomi")
                        end,
                        separator = true,
                        sub_item_table = {
                            {
                                text = _("Open Rakuyomi"),
                                checked_func = function() return config.manga_action ~= "folder" end,
                                callback = function()
                                    config.manga_action = "rakuyomi"
                                    G_reader_settings:saveSetting("bottom_navbar", config)
                                end,
                            },
                            {
                                text_func = function()
                                    if config.manga_action == "folder" and config.manga_folder ~= "" then
                                        local util = require("util")
                                        local _dir, folder_name = util.splitFilePathName(config.manga_folder)
                                        return _("Open folder: ") .. folder_name
                                    end
                                    return _("Open folder")
                                end,
                                checked_func = function() return config.manga_action == "folder" end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    local PathChooser = require("ui/widget/pathchooser")
                                    local start_path = config.manga_folder ~= "" and config.manga_folder
                                        or G_reader_settings:readSetting("lastdir") or "/"
                                    local path_chooser = PathChooser:new{
                                        select_file = false,
                                        show_files = false,
                                        path = start_path,
                                        onConfirm = function(dir_path)
                                            config.manga_action = "folder"
                                            config.manga_folder = dir_path
                                            G_reader_settings:saveSetting("bottom_navbar", config)
                                            if touchmenu_instance then
                                                touchmenu_instance:updateItems()
                                            end
                                        end,
                                    }
                                    UIManager:show(path_chooser)
                                end,
                            },
                        },
                    },
                    {
                        text = _("News"),
                        checked_func = function() return config.show_tabs.news end,
                        callback = function()
                            config.show_tabs.news = not config.show_tabs.news
                            G_reader_settings:saveSetting("bottom_navbar", config)
                        end,
                    },
                    {
                        text_func = function()
                            if config.news_action == "folder" then
                                return _("News tab action: ") .. _("Folder")
                            end
                            return _("News tab action: ") .. _("QuickRSS")
                        end,
                        separator = true,
                        sub_item_table = {
                            {
                                text = _("Open QuickRSS"),
                                checked_func = function() return config.news_action ~= "folder" end,
                                callback = function()
                                    config.news_action = "quickrss"
                                    G_reader_settings:saveSetting("bottom_navbar", config)
                                end,
                            },
                            {
                                text_func = function()
                                    if config.news_action == "folder" and config.news_folder ~= "" then
                                        local util = require("util")
                                        local _dir, folder_name = util.splitFilePathName(config.news_folder)
                                        return _("Open folder: ") .. folder_name
                                    end
                                    return _("Open folder")
                                end,
                                checked_func = function() return config.news_action == "folder" end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    local PathChooser = require("ui/widget/pathchooser")
                                    local start_path = config.news_folder ~= "" and config.news_folder
                                        or G_reader_settings:readSetting("lastdir") or "/"
                                    local path_chooser = PathChooser:new{
                                        select_file = false,
                                        show_files = false,
                                        path = start_path,
                                        onConfirm = function(dir_path)
                                            config.news_action = "folder"
                                            config.news_folder = dir_path
                                            G_reader_settings:saveSetting("bottom_navbar", config)
                                            if touchmenu_instance then
                                                touchmenu_instance:updateItems()
                                            end
                                        end,
                                    }
                                    UIManager:show(path_chooser)
                                end,
                            },
                        },
                    },
                    {
                        text = _("Continue"),
                        checked_func = function() return config.show_tabs.continue end,
                        callback = function()
                            config.show_tabs.continue = not config.show_tabs.continue
                            G_reader_settings:saveSetting("bottom_navbar", config)
                        end,
                    },
                    {
                        text = _("History"),
                        checked_func = function() return config.show_tabs.history end,
                        callback = function()
                            config.show_tabs.history = not config.show_tabs.history
                            G_reader_settings:saveSetting("bottom_navbar", config)
                        end,
                    },
                    {
                        text = _("Favorites"),
                        checked_func = function() return config.show_tabs.favorites end,
                        callback = function()
                            config.show_tabs.favorites = not config.show_tabs.favorites
                            G_reader_settings:saveSetting("bottom_navbar", config)
                        end,
                    },
                    {
                        text = _("Collections"),
                        checked_func = function() return config.show_tabs.collections end,
                        callback = function()
                            config.show_tabs.collections = not config.show_tabs.collections
                            G_reader_settings:saveSetting("bottom_navbar", config)
                        end,
                    },
                },
            },
            {
                text = _("Refresh navbar"),
                keep_menu_open = true,
                separator = true,
                callback = function()
                    local fm = FileManager.instance
                    if fm then
                        injectNavbar(fm)
                        UIManager:setDirty(fm, "ui")
                    end
                end,
            },
        },
    }

    orig_setUpdateItemTable(self)
end
