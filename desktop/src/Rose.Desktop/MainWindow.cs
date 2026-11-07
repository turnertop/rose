using System.Diagnostics;
using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform.Storage;
using Avalonia.Styling;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Rose.Core;
using Rose.Imaging;
using Location = Rose.Core.Location;

namespace Rose.Desktop;

public sealed class MainWindow : Window
{
    public LibraryController Library { get; }
    public GalleryControl Gallery { get; }
    public TextBox SearchField { get; } = new() { Name = "SearchField", PlaceholderText = "Search this view", Width = 260, CornerRadius = new(14), VerticalContentAlignment = VerticalAlignment.Center };
    public ScrollViewer GalleryScroll { get; } = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    public ImageViewport Viewport { get; } = new();
    public WindowPlacementController Placement { get; }
    public bool ViewerOpen => _viewer.IsVisible;
    public Location Location { get; private set; } = Location.All;
    private readonly ThumbnailService _thumbnails;
    private readonly Grid _root = new() { RowDefinitions = new("Auto,*") };
    private readonly Grid _body = new() { ColumnDefinitions = new("240,*,300"), Margin = new(16, 0, 16, 16), ColumnSpacing = 16 };
    private readonly StackPanel _sidebarContents = new() { Spacing = 5 };
    private readonly StackPanel _folders = new() { Spacing = 2 };
    private readonly StackPanel _collections = new() { Spacing = 2 };
    private readonly StackPanel _tagsNav = new() { Spacing = 2 };
    private readonly Border _sidebar = new() { Padding = new(16), CornerRadius = new(22) };
    private readonly Border _galleryPanel = new() { Padding = new(20), CornerRadius = new(24), BorderThickness = new(1), BorderBrush = Brush.Parse("#80FFFFFF") };
    private readonly Border _inspector = new() { Padding = new(20), CornerRadius = new(24), BorderThickness = new(1), BorderBrush = Brush.Parse("#80FFFFFF") };
    private readonly ScrollViewer _detailsScroll = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, IsVisible = false };
    private readonly GridSplitter _sidebarSplitter = new() { Width = 6, HorizontalAlignment = HorizontalAlignment.Right, ResizeDirection = GridResizeDirection.Columns, ResizeBehavior = GridResizeBehavior.CurrentAndNext, Background = Brushes.Transparent };
    private readonly GridSplitter _inspectorSplitter = new() { Width = 6, HorizontalAlignment = HorizontalAlignment.Left, ResizeDirection = GridResizeDirection.Columns, ResizeBehavior = GridResizeBehavior.PreviousAndCurrent, Background = Brushes.Transparent };
    private readonly TextBlock _heading = new() { Text = "All images", FontSize = 29, FontWeight = FontWeight.Bold, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock _count = new() { FontSize = 12, Opacity = .65 };
    private readonly TextBlock _breadcrumb = new() { Text = "Your image library", FontSize = 13, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock _status = new() { FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock _hint = new() { Text = "Space to scroll · Shift Space to scroll up", FontSize = 11, Opacity = .55, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock _empty = new() { Text = "A home for your images.\nOpen a folder to begin.", FontSize = 18, TextAlignment = TextAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false };
    private readonly Slider _size = new() { Minimum = 125, Maximum = 300, Width = 130, VerticalAlignment = VerticalAlignment.Center };
    private readonly Button _all; private readonly Button _favorites; private readonly Button _recent;
    private readonly Dictionary<DisplayMode, Button> _modes = [];
    private readonly CheckBox _recursive = new() { Content = "Include subfolders", FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
    private static readonly (AssetSort Value, string Title)[] SortChoices =
    [
        (AssetSort.Name, "Name"), (AssetSort.Added, "Date added"), (AssetSort.Modified, "Date modified"),
        (AssetSort.Created, "Date created"), (AssetSort.Size, "File size"), (AssetSort.Dimensions, "Dimensions")
    ];
    private readonly ComboBox _sort = new() { Name = "SortField", ItemsSource = SortChoices.Select(x => x.Title).ToArray(), MinWidth = 130 };
    private readonly Button _ascending;
    private readonly TextBlock _inspectorEmpty = new() { Text = "Something will catch your eye.\n\nSelect an image to see its details,\nadd tags, or leave a note.", TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Opacity = .65 };
    private readonly StackPanel _details = new() { Spacing = 14, IsVisible = false };
    private readonly Image _preview = new() { Height = 200, Stretch = Stretch.Uniform };
    private readonly TextBlock _fileName = new() { FontSize = 17, FontWeight = FontWeight.SemiBold, TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock _fileDetails = new() { FontSize = 11, Opacity = .65, TextWrapping = TextWrapping.Wrap };
    private readonly Button _favoriteButton;
    private readonly TextBox _tags = new() { PlaceholderText = "Add tags, separated by commas", CornerRadius = new(10) };
    private readonly TextBox _notes = new() { PlaceholderText = "A few thoughts to return to…", AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 200, CornerRadius = new(12) };
    private readonly ComboBox _collectionPicker = new() { PlaceholderText = "Choose a collection", HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly Border _viewer = new() { IsVisible = false, Padding = new(16) };
    private readonly TextBlock _viewerTitle = new() { VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, FontWeight = FontWeight.SemiBold };
    private readonly TextBlock _zoomLabel = new() { VerticalAlignment = VerticalAlignment.Center, Width = 55, TextAlignment = TextAlignment.Center };
    private ImageAsset? _viewerAsset;
    private ImageAsset? _inspected;
    private CancellationTokenSource? _previewCancellation;
    private CancellationTokenSource? _viewerCancellation;
    private Bitmap? _previewBitmap;
    private string? _previewKey;
    private bool _updating; private bool _spaceDown; private bool _closingReady; private bool _closingPending; private bool _isDisposed;
    private double _browseOffset;
    private string _previousSearch = "";
    private string _sidebarSignature = "";
    private string _appliedTheme = "";
    private Window? _settings;
    private readonly DispatcherTimer _searchDelay = new() { Interval = TimeSpan.FromMilliseconds(110) };

    public MainWindow() : this(new StateStore(), true) { }
    public MainWindow(StateStore store, bool initialize)
    {
        Library = new(store); _thumbnails = new(store.CachePath); Gallery = new(_thumbnails);
        Title = "Rose"; Width = 1280; Height = 840; MinWidth = 860; MinHeight = 540;
        Background = Brush.Parse("#FFE2ED");
        Icon = new WindowIcon(Avalonia.Platform.AssetLoader.Open(new Uri("avares://Rose/Assets/Rose.ico")));
        _all = ActionButton("▧  All images", () => Navigate(Location.All));
        _favorites = ActionButton("☆  Favorites", () => Navigate(new(LocationKind.Favorites)));
        _recent = ActionButton("◷  Recently viewed", () => Navigate(new(LocationKind.Recent)));
        _favoriteButton = ActionButton("☆ Favorite", ToggleFavorite);
        _ascending = ActionButton("↑", () => { Library.State.Preferences.Ascending = !Library.State.Preferences.Ascending; Library.Touch(); });
        Content = _root;
        BuildToolbar(); BuildSidebar(); BuildGallery(); BuildInspector(); BuildViewer();
        Place(_body, _sidebarSplitter, 0); Place(_body, _inspectorSplitter, 2);
        _sidebarSplitter.DragCompleted += (_, _) => { Library.State.Preferences.SidebarWidth = _body.ColumnDefinitions[0].ActualWidth; Library.Touch(); };
        _inspectorSplitter.DragCompleted += (_, _) => { Library.State.Preferences.InspectorWidth = _body.ColumnDefinitions[2].ActualWidth; Library.Touch(); };
        SizeChanged += (_, _) => UpdatePanelWidths();
        Grid.SetRow(_body, 1); _root.Children.Add(_body);
        _root.Children.Add(_viewer); Grid.SetRowSpan(_viewer, 2); _viewer.ZIndex = 10;
        Library.Changed += RefreshView;
        Gallery.SelectionChanged += UpdateInspector;
        Gallery.OpenRequested += asset => _ = OpenViewerAsync(asset);
        Gallery.ImageMenuRequested += ShowImageMenu;
        GalleryScroll.ScrollChanged += (_, _) => Gallery.SetViewport(GalleryScroll.Offset.Y, GalleryScroll.Viewport.Height);
        GalleryScroll.SizeChanged += (_, _) => Gallery.SetViewport(GalleryScroll.Offset.Y, GalleryScroll.Viewport.Height);
        SearchField.TextChanged += (_, _) =>
        {
            if (_updating) return;
            var query = SearchField.Text ?? "";
            if (_previousSearch.Length == 0 && query.Length > 0) _browseOffset = GalleryScroll.Offset.Y;
            var cleared = _previousSearch.Length > 0 && query.Length == 0; _previousSearch = query;
            _searchDelay.Stop();
            if (cleared) { RefreshView(); ReturnToBrowsing(false); Dispatcher.UIThread.Post(() => SetOffset(_browseOffset), DispatcherPriority.Loaded); }
            else _searchDelay.Start();
        };
        _searchDelay.Tick += (_, _) => { _searchDelay.Stop(); RefreshView(); SetOffset(0); };
        _size.PropertyChanged += (_, e) => { if (!_updating && e.Property == RangeBase.ValueProperty) { Library.State.Preferences.ThumbnailSize = _size.Value; Library.Touch(); } };
        _recursive.IsCheckedChanged += (_, _) => { if (!_updating) { Library.State.Preferences.IncludeSubfolders = _recursive.IsChecked == true; Library.Touch(); } };
        _sort.SelectionChanged += (_, _) =>
        {
            if (_updating || _sort.SelectedIndex < 0 || _sort.SelectedIndex >= SortChoices.Length) return;
            var selected = SortChoices[_sort.SelectedIndex].Value;
            var preferences = Library.State.Preferences;
            if (selected == AssetSort.Added && preferences.Sort != selected) preferences.Ascending = false;
            preferences.Sort = selected;
            Library.Touch();
        };
        _tags.KeyDown += (_, e) => { if (e.Key == Key.Enter) { SaveTags(); ReturnToBrowsing(false); e.Handled = true; } };
        _tags.LostFocus += (_, _) => SaveTags();
        _notes.TextChanged += (_, _) => { if (!_updating && _inspected is { } asset) Library.SetAnnotation(asset, CurrentAsset(asset).Annotation with { Note = _notes.Text ?? "" }); };
        AddHandler(KeyDownEvent, OnKeyDown, RoutingStrategies.Tunnel);
        AddHandler(KeyUpEvent, (_, e) => { if (e.Key == Key.Space) _spaceDown = false; }, RoutingStrategies.Tunnel, true);
        AddHandler(TextInputEvent, OnTextInput, RoutingStrategies.Tunnel);
        AddHandler(PointerPressedEvent, OnBackgroundPointer, RoutingStrategies.Tunnel);
        Deactivated += (_, _) => _spaceDown = false;
        PropertyChanged += (_, e) => { if (e.Property == ActualThemeVariantProperty) ApplyTheme(); };
        DragDrop.SetAllowDrop(this, true);
        AddHandler(DragDrop.DragOverEvent, (_, e) => { e.DragEffects = e.DataTransfer.Contains(DataFormat.File) ? DragDropEffects.Copy : DragDropEffects.None; e.Handled = true; });
        AddHandler(DragDrop.DropEvent, async (_, e) =>
        {
            foreach (var item in e.DataTransfer.TryGetFiles() ?? []) if (item.TryGetLocalPath() is { } path && Directory.Exists(path)) await Library.AddFolderAsync(path);
            e.Handled = true;
        });
        Opened += async (_, _) =>
        {
            ReturnToBrowsing(false);
            if (initialize) await Library.InitializeAsync(false);
            ApplyTheme(); RefreshView();
            if (initialize && Library.CanSave) _ = Library.RefreshAsync();
        };
        Closing += OnClosing;
        Closed += (_, _) => DisposeResources();
        Placement = new(this, store.DirectoryPath);
        Placement.SaveFailed += message => Library.Report("Could not remember the window layout: " + message);
        ApplyTheme(); RefreshView();
    }
    public static Button ActionButton(string title, Action action)
    {
        var button = new Button { Content = title, Padding = new(11, 8), CornerRadius = new(11), Background = Brushes.Transparent, BorderThickness = new(0), HorizontalContentAlignment = HorizontalAlignment.Left };
        button.Click += (_, _) => action(); AutomationProperties.SetName(button, title); return button;
    }
    private static TextBlock Caption(string text) => new() { Text = text.ToUpperInvariant(), FontSize = 10, LetterSpacing = 2, Opacity = .6, Margin = new(4, 16, 0, 6) };
    private static Grid Place(Grid grid, Control control, int column, int row = 0) { Grid.SetColumn(control, column); Grid.SetRow(control, row); grid.Children.Add(control); return grid; }
    private void BuildToolbar()
    {
        var bar = new Grid { ColumnDefinitions = new("Auto,*,Auto,Auto,Auto"), ColumnSpacing = 10, Margin = new(24, 16, 24, 18) };
        var sidebarToggle = ActionButton("◧", () => { Library.State.Preferences.SidebarVisible = !Library.State.Preferences.SidebarVisible; Library.Touch(); });
        ToolTip.SetTip(sidebarToggle, "Toggle sidebar (Ctrl+B)"); AutomationProperties.SetName(sidebarToggle, "Toggle sidebar");
        Place(bar, sidebarToggle, 0); Place(bar, _breadcrumb, 1); Place(bar, SearchField, 2);
        var inspectorToggle = ActionButton("◨", () => { Library.State.Preferences.InspectorVisible = !Library.State.Preferences.InspectorVisible; Library.Touch(); });
        ToolTip.SetTip(inspectorToggle, "Toggle inspector (Ctrl+I)"); AutomationProperties.SetName(inspectorToggle, "Toggle inspector"); Place(bar, inspectorToggle, 3);
        var more = ActionButton("•••", () => { });
        var menu = new ContextMenu { ItemsSource = new MenuItem[] {
            Menu("Open a folder…", () => _ = OpenFolderAsync()), Menu("Refresh folders", () => _ = Library.RefreshAsync()),
            Menu("New collection…", () => _ = NewCollectionAsync()), Menu("Settings…", ShowSettings) } };
        more.Click += (_, _) => menu.Open(more); Place(bar, more, 4); _root.Children.Add(bar);
    }
    private void BuildSidebar()
    {
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Margin = new(3, 6, 0, 24) };
        brand.Children.Add(new Image { Width = 48, Height = 48, Source = new Bitmap(Avalonia.Platform.AssetLoader.Open(new Uri("avares://Rose/Assets/Rose.png"))) });
        var title = new StackPanel(); title.Children.Add(new TextBlock { Text = "rose", FontFamily = new("Georgia"), FontSize = 34, FontWeight = FontWeight.Bold });
        title.Children.Add(new TextBlock { Text = "A HOME FOR YOUR IMAGES", FontSize = 8, LetterSpacing = 1.5, Opacity = .6 }); brand.Children.Add(title);
        _sidebarContents.Children.Add(brand);
        foreach (var button in new[] { _all, _favorites, _recent }) { button.HorizontalAlignment = HorizontalAlignment.Stretch; _sidebarContents.Children.Add(button); }
        var foldersHeader = new Grid { ColumnDefinitions = new("*,Auto") }; Place(foldersHeader, Caption("Folders"), 0); Place(foldersHeader, ActionButton("+", () => _ = OpenFolderAsync()), 1);
        _sidebarContents.Children.Add(foldersHeader); _sidebarContents.Children.Add(_folders);
        var collectionsHeader = new Grid { ColumnDefinitions = new("*,Auto") }; Place(collectionsHeader, Caption("Collections"), 0); Place(collectionsHeader, ActionButton("+", () => _ = NewCollectionAsync()), 1);
        _sidebarContents.Children.Add(collectionsHeader); _sidebarContents.Children.Add(_collections);
        _sidebarContents.Children.Add(Caption("Tags")); _sidebarContents.Children.Add(_tagsNav);
        var layout = new Grid { RowDefinitions = new("*,Auto,Auto") };
        layout.Children.Add(new ScrollViewer { Content = _sidebarContents, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
        Place(layout, ActionButton("▱  Open a folder", () => _ = OpenFolderAsync()), 0, 1);
        Place(layout, new TextBlock { Text = "Local by nature.", FontSize = 11, Opacity = .5, Margin = new(10, 12, 0, 0) }, 0, 2);
        _sidebar.Child = layout; Place(_body, _sidebar, 0);
    }
    private void BuildGallery()
    {
        var grid = new Grid { RowDefinitions = new("Auto,Auto,*,Auto"), RowSpacing = 16 };
        var header = new Grid { ColumnDefinitions = new("*,Auto") };
        var titles = new StackPanel { Spacing = 5 }; titles.Children.Add(_heading); titles.Children.Add(_count); Place(header, titles, 0);
        var modes = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2, VerticalAlignment = VerticalAlignment.Top };
        foreach (var mode in Enum.GetValues<DisplayMode>()) { var button = ActionButton(mode.ToString(), () => { Library.State.Preferences.DisplayMode = mode; Library.Touch(); }); modes.Children.Add(button); _modes[mode] = button; }
        Place(header, new Border { CornerRadius = new(16), Background = Brush.Parse("#208C7D86"), Padding = new(4), Child = modes }, 1); grid.Children.Add(header);
        var controls = new WrapPanel { Orientation = Orientation.Horizontal };
        foreach (var control in new Control[] { _ascending, _sort, _recursive, _size }) { control.Margin = new(0, 0, 12, 4); controls.Children.Add(control); }
        AutomationProperties.SetName(_size, "Thumbnail size"); Place(grid, controls, 0, 1);
        var galleryLayer = new Grid(); GalleryScroll.Content = Gallery; galleryLayer.Children.Add(GalleryScroll); galleryLayer.Children.Add(_empty); Place(grid, galleryLayer, 0, 2);
        var footer = new Grid { ColumnDefinitions = new("*,Auto") }; Place(footer, _status, 0); Place(footer, _hint, 1); Place(grid, footer, 0, 3);
        _galleryPanel.Child = grid; Place(_body, _galleryPanel, 1);
    }
    private void BuildInspector()
    {
        _details.Children.Add(Caption("A closer look"));
        var previewButton = ActionButton("", () => { if (_inspected is { } asset) _ = OpenViewerAsync(asset); }); previewButton.Content = _preview; previewButton.HorizontalAlignment = HorizontalAlignment.Stretch;
        AutomationProperties.SetName(previewButton, "Open selected image"); _details.Children.Add(previewButton);
        _details.Children.Add(_fileName); _details.Children.Add(_fileDetails);
        var actions = new WrapPanel { Orientation = Orientation.Horizontal };
        actions.Children.Add(_favoriteButton);
        actions.Children.Add(ActionButton("Show folder", () => { if (_inspected is { } asset) Reveal(asset); }));
        actions.Children.Add(ActionButton("Copy link", () => { if (_inspected is { } asset) _ = CopyLinkAsync(asset); }));
        actions.Children.Add(ActionButton("Recycle…", () => { if (_inspected is { } asset) _ = RecycleAsync(asset); }));
        _details.Children.Add(actions); _details.Children.Add(Caption("Tags")); _details.Children.Add(_tags);
        _details.Children.Add(Caption("Collections")); _details.Children.Add(_collectionPicker);
        _details.Children.Add(ActionButton("Add / remove selection", ToggleCollection));
        _details.Children.Add(Caption("Notes")); _details.Children.Add(_notes);
        AutomationProperties.SetName(_notes, "Image notes"); AutomationProperties.SetName(_tags, "Image tags");
        var layer = new Grid(); layer.Children.Add(_inspectorEmpty); _detailsScroll.Content = _details; layer.Children.Add(_detailsScroll);
        _inspector.Child = layer; Place(_body, _inspector, 2);
    }
    private void BuildViewer()
    {
        var grid = new Grid { RowDefinitions = new("Auto,*,Auto"), RowSpacing = 10 };
        var top = new Grid { ColumnDefinitions = new("Auto,*,Auto,Auto,Auto"), ColumnSpacing = 10 };
        Place(top, ActionButton("← Back", CloseViewer), 0); Place(top, _viewerTitle, 1);
        Place(top, ActionButton("☆ Favorite", ToggleFavorite), 2);
        Place(top, ActionButton("Fullscreen", () => Placement.ToggleFullScreen()), 3);
        Place(top, ActionButton("Settings", ShowSettings), 4); grid.Children.Add(top); Place(grid, Viewport, 0, 1);
        var tools = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Spacing = 8 };
        tools.Children.Add(ActionButton("‹ Previous", () => MoveViewer(-1)));
        tools.Children.Add(ActionButton("−", () => Viewport.SetZoom(Viewport.Zoom / 1.25))); tools.Children.Add(_zoomLabel);
        tools.Children.Add(ActionButton("+", () => Viewport.SetZoom(Viewport.Zoom * 1.25))); tools.Children.Add(ActionButton("Fit", Viewport.Fit));
        tools.Children.Add(ActionButton("100%", () => { if (_viewerAsset is { } asset) Viewport.ActualSize(asset.Width); }));
        tools.Children.Add(ActionButton("Next ›", () => MoveViewer(1))); Place(grid, tools, 0, 2); _viewer.Child = grid;
        Viewport.ZoomChanged += () => _zoomLabel.Text = $"{Viewport.SourcePixelScale * 100:0}%";
    }
    public void RefreshView()
    {
        if (_isDisposed) return;
        var preferences = Library.State.Preferences;
        if (_appliedTheme != preferences.Theme) { _appliedTheme = preferences.Theme; ApplyTheme(); }
        _updating = true;
        _size.Value = preferences.ThumbnailSize; _recursive.IsChecked = preferences.IncludeSubfolders;
        _sort.SelectedIndex = Array.FindIndex(SortChoices, x => x.Value == preferences.Sort);
        ToolTip.SetTip(_sort, preferences.Sort == AssetSort.Added
            ? "Date added: newest first when selected. Existing files use an estimated local creation date."
            : "Sort images");
        _ascending.Content = preferences.Ascending ? "↑" : "↓";
        _sidebar.IsVisible = preferences.SidebarVisible; _inspector.IsVisible = preferences.InspectorVisible;
        UpdatePanelWidths();
        foreach (var (mode, button) in _modes) { button.Background = mode == preferences.DisplayMode ? Brush.Parse("#30EF3585") : Brushes.Transparent; button.Foreground = mode == preferences.DisplayMode ? GalleryControl.Accent : Foreground; }
        var assets = LibraryQuery.Filter(Library.State, Location, SearchField.Text ?? "");
        Gallery.SetItems(assets, preferences.DisplayMode, preferences.ThumbnailSize);
        _heading.Text = Location.Kind switch { LocationKind.All => "All images", LocationKind.Favorites => "Favorites", LocationKind.Recent => "Recently viewed", LocationKind.Folder => new VaultRoot(Location.Value).Name,
            LocationKind.Collection => Library.State.Collections.FirstOrDefault(x => x.Id == Location.Value)?.Name ?? "Collection", _ => "#" + Location.Value };
        _breadcrumb.Text = Location.Kind == LocationKind.Folder ? "▱  " + new VaultRoot(Location.Value).Name : "Your image library";
        _count.Text = $"{assets.Length:N0} images" + (Location.Kind == LocationKind.Folder && preferences.IncludeSubfolders ? " · including subfolders" : "");
        _empty.IsVisible = assets.Length == 0; _empty.Text = Library.Scanning ? "Finding your images…" : !string.IsNullOrEmpty(SearchField.Text) ? "No images match your search." : Library.State.Roots.Count == 0 ? "A home for your images.\nOpen a folder to begin." : "Nothing here yet.";
        _status.Text = Library.CanSave ? Library.Status : "Saved library couldn't be loaded · Connections and preferences are temporary";
        ToolTip.SetTip(_status, Library.Status);
        _hint.Text = Gallery.Selected.Count == 0 ? "Space to scroll · Shift Space to scroll up" : "Space to take a closer look";
        Viewport.ScrollToZoom = preferences.ScrollToZoom;
        UpdateSidebar(); _updating = false; UpdateInspector();
    }
    private void UpdatePanelWidths()
    {
        var prefs = Library.State.Preferences;
        var available = Math.Max(860, ClientSize.Width > 0 ? ClientSize.Width : Width) - 64;
        _body.ColumnDefinitions[0].MinWidth = prefs.SidebarVisible ? 180 : 0;
        _body.ColumnDefinitions[2].MinWidth = prefs.InspectorVisible ? 240 : 0;
        _body.ColumnDefinitions[0].Width = new(prefs.SidebarVisible ? Math.Clamp(prefs.SidebarWidth, 180, Math.Max(180, Math.Min(420, available * .3))) : 0);
        _body.ColumnDefinitions[2].Width = new(prefs.InspectorVisible ? Math.Clamp(prefs.InspectorWidth, 240, Math.Max(240, Math.Min(480, available * .3))) : 0);
        _sidebarSplitter.IsVisible = prefs.SidebarVisible; _inspectorSplitter.IsVisible = prefs.InspectorVisible;
    }
    private void UpdateSidebar()
    {
        var state = Library.State;
        _all.Content = $"▧  All images   {state.Assets.Count:N0}"; _favorites.Content = $"☆  Favorites   {state.Assets.Count(x => x.Annotation.IsFavorite):N0}"; _recent.Content = $"◷  Recently viewed   {state.RecentPaths.Count:N0}";
        foreach (var (button, kind) in new[] { (_all, LocationKind.All), (_favorites, LocationKind.Favorites), (_recent, LocationKind.Recent) }) button.Background = Location.Kind == kind ? Brush.Parse("#30EF3585") : Brushes.Transparent;
        var signature = string.Join('|', state.Roots.Select(x => x.Path + x.Available)) + string.Join('|', state.Directories.Values.SelectMany(x => x)) +
            string.Join('|', state.Collections.Select(x => x.Id + x.Name + x.Paths.Length)) + string.Join('|', state.Preferences.ExpandedFolders) + Location +
            string.Join('|', state.Assets.Select(x => x.Annotation.IsFavorite + string.Join(',', x.Annotation.Tags)));
        if (signature == _sidebarSignature) return; _sidebarSignature = signature;
        _folders.Children.Clear(); _collections.Children.Clear(); _tagsNav.Children.Clear();
        var expanded = state.Preferences.ExpandedFolders.ToHashSet(PathRules.Comparer);
        var directCounts = state.Assets.GroupBy(x => x.FolderPath, PathRules.Comparer).ToDictionary(x => x.Key, x => x.Count(), PathRules.Comparer);
        foreach (var root in state.Roots)
        {
            var paths = state.Directories.GetValueOrDefault(root.Path, [root.Path]).Distinct(PathRules.Comparer).ToArray();
            var children = paths.Where(x => !PathRules.Comparer.Equals(x, root.Path)).GroupBy(x => Path.GetDirectoryName(x) ?? "", PathRules.Comparer)
                .ToDictionary(x => x.Key, x => x.OrderBy(p => Path.GetFileName(p), Comparer<string>.Create(LibraryQuery.NaturalCompare)).ToArray(), PathRules.Comparer);
            void AddFolder(string path, int depth)
            {
                var row = new Grid { ColumnDefinitions = new("20,*"), Margin = new(depth * 13, 0, 0, 0) };
                if (children.ContainsKey(path)) Place(row, ActionButton(expanded.Contains(path) ? "⌄" : "›", () =>
                {
                    if (!expanded.Add(path)) expanded.Remove(path); state.Preferences.ExpandedFolders = expanded.ToArray(); Library.Touch();
                }), 0);
                var total = state.Assets.Count(x => PathRules.IsWithin(x.Path, path));
                var button = ActionButton("▱  " + new VaultRoot(path).Name + (path == root.Path && !root.Available ? " (offline)" : "") + $"   {total}", () => Navigate(new(LocationKind.Folder, path)));
                button.Padding = new(4, 8); button.HorizontalAlignment = HorizontalAlignment.Stretch;
                button.Content = new TextBlock { Text = button.Content?.ToString(), TextTrimming = TextTrimming.CharacterEllipsis };
                button.Background = Location.Kind == LocationKind.Folder && PathRules.Comparer.Equals(Location.Value, path) ? Brush.Parse("#30EF3585") : Brushes.Transparent;
                ToolTip.SetTip(button, path);
                if (PathRules.Comparer.Equals(path, root.Path)) button.ContextMenu = new ContextMenu { ItemsSource = new[] { Menu("Remove folder connection", () => Library.RemoveRoot(root.Path)) } };
                Place(row, button, 1); _folders.Children.Add(row);
                if (expanded.Contains(path) && children.TryGetValue(path, out var nested)) foreach (var child in nested) AddFolder(child, depth + 1);
            }
            AddFolder(root.Path, 0);
        }
        foreach (var collection in state.Collections)
        {
            var button = ActionButton($"◇  {collection.Name}   {collection.Paths.Length}", () => Navigate(new(LocationKind.Collection, collection.Id)));
            button.ContextMenu = new ContextMenu { ItemsSource = new[] { Menu("Rename…", () => _ = RenameCollectionAsync(collection)), Menu("Remove collection", () => { state.Collections.RemoveAll(x => x.Id == collection.Id); if (Location.Value == collection.Id) Location = Location.All; Library.Touch(); }) } };
            _collections.Children.Add(button);
        }
        foreach (var tag in state.Assets.SelectMany(x => x.Annotation.Tags).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x)) _tagsNav.Children.Add(ActionButton("# " + tag, () => Navigate(new(LocationKind.Tag, tag))));
        var selectedCollection = (_collectionPicker.SelectedItem as ImageCollection)?.Id;
        _collectionPicker.ItemsSource = state.Collections.ToArray();
        _collectionPicker.ItemTemplate = new Avalonia.Controls.Templates.FuncDataTemplate<ImageCollection>((item, _) => new TextBlock { Text = item?.Name });
        _collectionPicker.SelectedItem = state.Collections.FirstOrDefault(x => x.Id == selectedCollection);
    }
    private ImageAsset CurrentAsset(ImageAsset asset) => Library.State.Assets.FirstOrDefault(x => PathRules.Comparer.Equals(x.Path, asset.Path)) ?? asset;
    private ImageAsset? SelectedAsset => Gallery.Items.FirstOrDefault(x => Gallery.Selected.Contains(x.Path));
    private void UpdateInspector()
    {
        var asset = SelectedAsset;
        _hint.Text = Gallery.Selected.Count == 0 ? "Space to scroll · Shift Space to scroll up" : "Space to take a closer look";
        _inspectorEmpty.IsVisible = asset is null; _details.IsVisible = asset is not null; _detailsScroll.IsVisible = asset is not null;
        if (asset is null) { _inspected = null; _previewCancellation?.Cancel(); _previewKey = null; _preview.Source = null; _previewBitmap?.Dispose(); _previewBitmap = null; return; }
        asset = CurrentAsset(asset); var changed = _inspected?.Path != asset.Path; _inspected = asset;
        _updating = true; _fileName.Text = asset.Name; _fileDetails.Text = asset.Details;
        _favoriteButton.Content = asset.Annotation.IsFavorite ? "★ Favorite" : "☆ Favorite";
        if (!_tags.IsFocused) _tags.Text = string.Join(", ", asset.Annotation.Tags);
        if (!_notes.IsFocused) _notes.Text = asset.Annotation.Note;
        _updating = false;
        if (Library.State.Preferences.InspectorVisible && _previewKey != ThumbnailService.Key(asset, 512)) _ = LoadPreviewAsync(asset);
    }
    private async Task LoadPreviewAsync(ImageAsset asset)
    {
        _previewCancellation?.Cancel(); _previewCancellation?.Dispose(); _previewCancellation = new(); var token = _previewCancellation.Token;
        _previewKey = ThumbnailService.Key(asset, 512);
        _preview.Source = null; _previewBitmap?.Dispose(); _previewBitmap = null;
        try
        {
            var data = await _thumbnails.RequestAsync(asset, 512, token);
            var bitmap = await Task.Run(() => new Bitmap(new MemoryStream(data, false)), token);
            if (token.IsCancellationRequested || _isDisposed) { bitmap.Dispose(); return; }
            _previewBitmap = bitmap; _preview.Source = bitmap;
        }
        catch (OperationCanceledException) { }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException) { Library.Report("Preview unavailable: " + e.Message); }
    }
    public void Navigate(Location location)
    {
        SaveTags(); Location = location; Gallery.ClearSelection();
        _updating = true; SearchField.Text = ""; _previousSearch = ""; _updating = false;
        _searchDelay.Stop(); _browseOffset = 0; RefreshView(); SetOffset(0); ReturnToBrowsing(false);
    }
    public void ReturnToBrowsing(bool clearSelection = true)
    {
        SaveTags();
        if (clearSelection) Gallery.ClearSelection();
        Gallery.Focus();
    }
    private void OnBackgroundPointer(object? sender, PointerPressedEventArgs e)
    {
        if (ViewerOpen || e.KeyModifiers != KeyModifiers.None || e.Source is not Visual source) return;
        var chain = source.GetSelfAndVisualAncestors().ToArray();
        if (chain.Contains(_inspector) || chain.Contains(Gallery)) return;
        if (chain.Any(x => x is TextBox or Button or ComboBox or Slider or CheckBox or MenuItem or ScrollBar or GridSplitter)) return;
        ReturnToBrowsing();
    }
    private void OnTextInput(object? sender, TextInputEventArgs e)
    {
        if (ViewerOpen || string.IsNullOrEmpty(e.Text) || e.Text.All(char.IsWhiteSpace)) return;
        var focused = FocusManager?.GetFocusedElement();
        if (focused is Visual visual && visual.GetSelfAndVisualAncestors().Any(x => x is TextBox)) return;
        SearchField.Focus(); SearchField.Text = e.Text; SearchField.CaretIndex = e.Text.Length; e.Handled = true;
    }
    public void OnKeyDown(object? sender, KeyEventArgs e)
    {
        var control = e.KeyModifiers.HasFlag(KeyModifiers.Control);
        if (ViewerOpen)
        {
            if (e.Key == Key.Space) { if (!_spaceDown) CloseViewer(); _spaceDown = true; e.Handled = true; }
            else if (e.Key == Key.Escape) { CloseViewer(); e.Handled = true; }
            else if (e.Key is Key.Left or Key.Right) { MoveViewer(e.Key == Key.Left ? -1 : 1); e.Handled = true; }
            else if (e.Key is Key.Add or Key.OemPlus) { Viewport.SetZoom(Viewport.Zoom * 1.25); e.Handled = true; }
            else if (e.Key is Key.Subtract or Key.OemMinus) { Viewport.SetZoom(Viewport.Zoom / 1.25); e.Handled = true; }
            else if (e.Key is Key.D0 or Key.NumPad0) { Viewport.Fit(); e.Handled = true; }
            else if (e.Key is Key.D1 or Key.NumPad1) { if (_viewerAsset is { } asset) Viewport.ActualSize(asset.Width); e.Handled = true; }
            else if (e.Key == Key.F) { Placement.ToggleFullScreen(); e.Handled = true; }
            else if (control && e.Key == Key.D) { ToggleFavorite(); e.Handled = true; }
            return;
        }
        if (control)
        {
            if (e.Key == Key.F) { SearchField.Focus(); SearchField.SelectAll(); e.Handled = true; return; }
            if (e.Key == Key.O) { _ = OpenFolderAsync(); e.Handled = true; return; }
            if (e.Key == Key.OemComma) { ShowSettings(); e.Handled = true; return; }
            if (e.Key == Key.B) { Library.State.Preferences.SidebarVisible = !Library.State.Preferences.SidebarVisible; Library.Touch(); e.Handled = true; return; }
            if (e.Key == Key.I) { Library.State.Preferences.InspectorVisible = !Library.State.Preferences.InspectorVisible; Library.Touch(); e.Handled = true; return; }
        }
        var focused = FocusManager?.GetFocusedElement();
        var textInput = focused is Visual visual && visual.GetSelfAndVisualAncestors().Any(x => x is TextBox);
        if (textInput)
        {
            if (e.Key == Key.Escape && SearchField.IsKeyboardFocusWithin) { ReturnToBrowsing(false); e.Handled = true; }
            return;
        }
        if (!control && e.Key != Key.Escape && focused is Visual controlVisual &&
            controlVisual.GetSelfAndVisualAncestors().Any(x => x is Button or ComboBox or Slider or CheckBox)) return;
        if (control && e.Key == Key.A) { Gallery.SelectAll(); e.Handled = true; }
        else if (control && e.Key == Key.D) { ToggleFavorite(); e.Handled = true; }
        else if (control && e.Key == Key.N) { _ = NewCollectionAsync(); e.Handled = true; }
        else if (control && e.Key is Key.D1 or Key.D2 or Key.D3) { Library.State.Preferences.DisplayMode = (DisplayMode)(e.Key - Key.D1); Library.Touch(); e.Handled = true; }
        else if (e.Key == Key.Escape) { ReturnToBrowsing(); e.Handled = true; }
        else if (e.Key == Key.Space)
        {
            if (SelectedAsset is { } selected) { if (!_spaceDown) _ = OpenViewerAsync(selected); }
            else Page(e.KeyModifiers.HasFlag(KeyModifiers.Shift) ? -1 : 1);
            _spaceDown = true; e.Handled = true;
        }
        else if (e.Key == Key.Enter && SelectedAsset is { } selected) { _ = OpenViewerAsync(selected); e.Handled = true; }
        else if (e.Key is Key.Left or Key.Right or Key.Up or Key.Down)
        {
            var index = Gallery.Navigate(e.Key == Key.Left ? -1 : e.Key == Key.Right ? 1 : 0, e.Key == Key.Up ? -1 : e.Key == Key.Down ? 1 : 0, e.KeyModifiers.HasFlag(KeyModifiers.Shift));
            if (index >= 0 && index < Gallery.Geometry.Frames.Length)
            {
                var frame = Gallery.Geometry.Frames[index]; if (frame.Y < GalleryScroll.Offset.Y) SetOffset(frame.Y); else if (frame.Bottom > GalleryScroll.Offset.Y + GalleryScroll.Viewport.Height) SetOffset(frame.Bottom - GalleryScroll.Viewport.Height);
            }
            e.Handled = true;
        }
        else if (e.Key is Key.PageDown or Key.PageUp) { Page(e.Key == Key.PageDown ? 1 : -1); e.Handled = true; }
        else if (e.Key is Key.Home or Key.End) { SetOffset(e.Key == Key.Home ? 0 : Gallery.Geometry.Height); e.Handled = true; }
    }
    public void Page(int direction) => SetOffset(GalleryScroll.Offset.Y + direction * GalleryScroll.Viewport.Height * .88);
    public void SetOffset(double y) => GalleryScroll.Offset = new(0, Math.Clamp(y, 0, Math.Max(0, Gallery.Geometry.Height - GalleryScroll.Viewport.Height)));
    public async Task OpenFolderAsync()
    {
        var folders = await StorageProvider.OpenFolderPickerAsync(new() { Title = "Choose an image folder", AllowMultiple = true });
        foreach (var folder in folders) if (folder.TryGetLocalPath() is { } path) { await Library.AddFolderAsync(path); Navigate(new(LocationKind.Folder, PathRules.Canonical(path))); }
    }
    private void SaveTags()
    {
        if (_updating || _inspected is not { } asset) return;
        var tags = (_tags.Text ?? "").Split(',').Select(x => x.Trim()).Where(x => x.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var current = CurrentAsset(asset);
        if (!tags.SequenceEqual(current.Annotation.Tags)) Library.SetAnnotation(current, current.Annotation with { Tags = tags });
    }
    private void ToggleFavorite()
    {
        var assets = ViewerOpen && _viewerAsset is { } viewed ? new[] { CurrentAsset(viewed) } : Gallery.Items.Where(x => Gallery.Selected.Contains(x.Path)).Select(CurrentAsset).ToArray();
        var favorite = assets.Any(x => !x.Annotation.IsFavorite);
        foreach (var asset in assets) Library.SetAnnotation(asset, asset.Annotation with { IsFavorite = favorite });
    }
    private void ToggleCollection()
    {
        if (_collectionPicker.SelectedItem is not ImageCollection collection || Gallery.Selected.Count == 0) return;
        var paths = collection.Paths.ToHashSet(PathRules.Comparer);
        if (Gallery.Selected.All(paths.Contains)) paths.ExceptWith(Gallery.Selected); else paths.UnionWith(Gallery.Selected);
        var index = Library.State.Collections.FindIndex(x => x.Id == collection.Id); Library.State.Collections[index] = collection with { Paths = paths.ToArray() }; Library.Touch();
    }
    private async Task NewCollectionAsync()
    {
        var name = await PromptAsync("New collection", "Give this collection a name", "Create");
        if (string.IsNullOrWhiteSpace(name)) return;
        var collection = new ImageCollection(Guid.NewGuid().ToString("N"), name.Trim(), Gallery.Selected.ToArray());
        Library.State.Collections.Add(collection); Navigate(new(LocationKind.Collection, collection.Id)); Library.Touch();
    }
    private async Task RenameCollectionAsync(ImageCollection collection)
    {
        var name = await PromptAsync("Rename collection", collection.Name, "Save", collection.Name);
        if (string.IsNullOrWhiteSpace(name)) return;
        var index = Library.State.Collections.FindIndex(x => x.Id == collection.Id); if (index >= 0) Library.State.Collections[index] = collection with { Name = name.Trim() }; Library.Touch();
    }
    private void ShowImageMenu(ImageAsset asset, Point point)
    {
        var menu = new ContextMenu { ItemsSource = new[] {
            Menu("Open image", () => _ = OpenViewerAsync(asset)), Menu(asset.Annotation.IsFavorite ? "Remove favorite" : "Favorite", ToggleFavorite),
            Menu("Show in Explorer", () => Reveal(asset)), Menu("Copy Markdown link", () => _ = CopyLinkAsync(asset)),
            Menu("New collection with selection…", () => _ = NewCollectionAsync()), Menu("Move to Recycle Bin…", () => _ = RecycleAsync(asset)) } };
        menu.Open(Gallery);
    }
    private static MenuItem Menu(string title, Action action) { var item = new MenuItem { Header = title }; item.Click += (_, _) => action(); return item; }
    private void Reveal(ImageAsset asset)
    {
        try
        {
            if (OperatingSystem.IsWindows()) { var info = new ProcessStartInfo("explorer.exe") { UseShellExecute = true }; info.ArgumentList.Add("/select,"); info.ArgumentList.Add(asset.Path); Process.Start(info); }
            else Process.Start(new ProcessStartInfo(OperatingSystem.IsMacOS() ? "open" : "xdg-open") { ArgumentList = { asset.FolderPath }, UseShellExecute = false });
        }
        catch (Exception e) { Library.Report("Could not open the folder: " + e.Message); }
    }
    private async Task CopyLinkAsync(ImageAsset asset)
    {
        if (Clipboard is { } clipboard) await clipboard.SetTextAsync($"![{asset.Name.Replace("]", "\\]")}]({new Uri(asset.Path).AbsoluteUri})");
    }
    private async Task RecycleAsync(ImageAsset asset)
    {
        if (!OperatingSystem.IsWindows()) { Library.Report("Recycle Bin actions are available in the Windows build."); return; }
        if (await PromptAsync("Move to Recycle Bin?", $"Move {asset.Name} and its Markdown sidecar to the Recycle Bin?", "Move to Recycle Bin", confirmation: true) is null) return;
        try
        {
            await Library.FlushAsync();
            await Task.Run(() =>
            {
                Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(asset.Path, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
                if (File.Exists(SidecarStore.PathFor(asset.Path))) Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(SidecarStore.PathFor(asset.Path), Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
            });
            if (ViewerOpen) CloseViewer(); await Library.RefreshAsync();
        }
        catch (Exception e) { Library.Report("Recycle Bin action did not finish: " + e.Message); await Library.RefreshAsync(); }
    }
    public async Task OpenViewerAsync(ImageAsset asset)
    {
        SaveTags(); _viewerCancellation?.Cancel(); _viewerCancellation?.Dispose(); _viewerCancellation = new(); var token = _viewerCancellation.Token;
        _viewerAsset = asset; _viewerTitle.Text = asset.Name; _viewer.IsVisible = true; Gallery.SuspendRequests(); Viewport.SourceWidth = asset.Width; Viewport.Message = "Loading image…"; Viewport.SetBitmap(null, true); Viewport.Focus(); Library.Remember(asset);
        try
        {
            var bitmap = await Task.Run(() => { var bytes = ImageDecoder.Decode(asset.Path, 4096, token); return new Bitmap(new MemoryStream(bytes, false)); }, token);
            if (token.IsCancellationRequested || _isDisposed) { bitmap.Dispose(); return; }
            Viewport.SetBitmap(bitmap, true);
            if (asset.Extension == "GIF") _ = PlayGifAsync(asset.Path, token);
        }
        catch (OperationCanceledException) { }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException)
        { if (!token.IsCancellationRequested) { Viewport.Message = "Could not open this image.\n" + e.Message; Viewport.InvalidateVisual(); } }
    }
    private async Task PlayGifAsync(string path, CancellationToken cancellation)
    {
        GifPlayback? playback = null;
        try
        {
            playback = await Task.Run(() => GifPlayback.Open(path), cancellation);
            if (playback is null) return;
            while (!cancellation.IsCancellationRequested)
            {
                var frame = await Task.Run(playback.Next, cancellation); if (frame is null) return;
                var bitmap = await Task.Run(() => new Bitmap(new MemoryStream(frame.Value.Data, false)), cancellation);
                if (cancellation.IsCancellationRequested || _isDisposed) { bitmap.Dispose(); return; }
                Viewport.SetBitmap(bitmap, false); await Task.Delay(frame.Value.Delay, cancellation);
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception e) when (e is IOException or ArgumentException) { Library.Report("Animation stopped: " + e.Message); }
        finally { if (playback is not null) await Task.Run(playback.Dispose); }
    }
    public void CloseViewer()
    {
        _viewerCancellation?.Cancel(); _viewer.IsVisible = false; _viewerAsset = null; Viewport.SetBitmap(null, true);
        Gallery.ResumeRequests(); Gallery.SetViewport(GalleryScroll.Offset.Y, GalleryScroll.Viewport.Height); ReturnToBrowsing(false);
    }
    private void MoveViewer(int delta)
    {
        if (_viewerAsset is null || Gallery.Items.Length == 0) return;
        var index = Array.FindIndex(Gallery.Items, x => PathRules.Comparer.Equals(x.Path, _viewerAsset.Path));
        index = Math.Clamp(index + delta, 0, Gallery.Items.Length - 1); Gallery.Select(index); _ = OpenViewerAsync(Gallery.Items[index]);
    }
    private void ApplyTheme()
    {
        if (Library is null) return;
        var preference = Library.State.Preferences.Theme;
        var variant = preference == "Dark rose" ? ThemeVariant.Dark : preference == "Pink" ? ThemeVariant.Light : ThemeVariant.Default;
        if (RequestedThemeVariant != variant) RequestedThemeVariant = variant;
        var dark = ActualThemeVariant == ThemeVariant.Dark;
        Background = new LinearGradientBrush { StartPoint = new(0, 0, RelativeUnit.Relative), EndPoint = new(1, 1, RelativeUnit.Relative), GradientStops = new() { new(Color.Parse(dark ? "#291A25" : "#FFD6E4"), 0), new(Color.Parse(dark ? "#20171F" : "#FFF1F7"), .6), new(Color.Parse(dark ? "#331B2B" : "#FFDEED"), 1) } };
        Foreground = Brush.Parse(dark ? "#F3E8EF" : "#342330");
        var panel = Brush.Parse(dark ? "#30212C" : "#FFF0F6");
        _sidebar.Background = Brush.Parse(dark ? "#291D26" : "#FFF4F9"); _galleryPanel.Background = panel; _inspector.Background = panel; _viewer.Background = panel;
        SearchField.Background = Brush.Parse(dark ? "#432B3B" : "#F9DFEC"); Gallery.Dark = dark; Viewport.Dark = dark; Gallery.InvalidateVisual(); Viewport.InvalidateVisual();
    }
    private void ShowSettings()
    {
        if (_settings is not null) { _settings.Activate(); return; }
        var dialog = new Window { Title = "Rose Settings", Width = 500, Height = 540, MinWidth = 420, MinHeight = 400, WindowStartupLocation = WindowStartupLocation.CenterOwner, RequestedThemeVariant = RequestedThemeVariant };
        var content = new StackPanel { Margin = new(24), Spacing = 16 };
        content.Children.Add(new TextBlock { Text = "Make yourself at home.", FontSize = 23, FontWeight = FontWeight.Bold });
        content.Children.Add(Caption("Appearance"));
        var theme = new ComboBox { ItemsSource = new[] { "Pink", "Dark rose", "Follow system" }, SelectedItem = Library.State.Preferences.Theme, HorizontalAlignment = HorizontalAlignment.Stretch };
        theme.SelectionChanged += (_, _) => { if (theme.SelectedItem is string value) { Library.State.Preferences.Theme = value; ApplyTheme(); dialog.RequestedThemeVariant = RequestedThemeVariant; Library.Touch(); } };
        content.Children.Add(theme); content.Children.Add(new TextBlock { Text = "Static pink surfaces keep the interface light while browsing large image folders.", TextWrapping = TextWrapping.Wrap, Opacity = .7 });
        content.Children.Add(Caption("Image viewer"));
        var scroll = new CheckBox { Content = "Scroll to zoom", IsChecked = Library.State.Preferences.ScrollToZoom };
        scroll.IsCheckedChanged += (_, _) => { Library.State.Preferences.ScrollToZoom = scroll.IsChecked == true; Library.Touch(); }; content.Children.Add(scroll);
        content.Children.Add(new TextBlock { Text = "When off, scrolling pans a zoomed image. Ctrl + wheel always zooms. Pinch zoom and drag to pan remain available.", TextWrapping = TextWrapping.Wrap, Opacity = .7 });
        content.Children.Add(Caption("Keyboard"));
        content.Children.Add(new TextBlock { Text = "Type to search · Ctrl+F to edit search\nSpace: scroll or open selection · Shift+Space: scroll up\nEscape: leave search / clear selection / close viewer\nCtrl+1 / 2 / 3: Fill / Fit / List\nCtrl+B: sidebar · Ctrl+I: inspector · Ctrl+D: favorite\nViewer: ← / →, + / −, 0 fit, 1 actual size, F fullscreen", TextWrapping = TextWrapping.Wrap, LineHeight = 23 });
        content.Children.Add(new TextBlock { Text = $"Rose for Windows · Preview {typeof(MainWindow).Assembly.GetName().Version?.ToString(3)}\nYour files stay in their folders. No account required.", FontSize = 11, Opacity = .6 });
        dialog.Content = new ScrollViewer { Content = content }; dialog.Closed += (_, _) => { _settings = null; if (ViewerOpen) Viewport.Focus(); else ReturnToBrowsing(false); }; _settings = dialog; dialog.Show(this);
    }
    private async Task<string?> PromptAsync(string title, string message, string affirmative, string initial = "", bool confirmation = false)
    {
        var dialog = new Window { Title = title, Width = 440, SizeToContent = SizeToContent.Height, CanResize = false, WindowStartupLocation = WindowStartupLocation.CenterOwner, RequestedThemeVariant = RequestedThemeVariant };
        var stack = new StackPanel { Margin = new(22), Spacing = 16 };
        stack.Children.Add(new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap });
        var input = new TextBox { Text = initial, PlaceholderText = "Name" }; if (!confirmation) stack.Children.Add(input);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 10 };
        actions.Children.Add(ActionButton("Cancel", () => dialog.Close(null)));
        var accept = ActionButton(affirmative, () => dialog.Close(confirmation ? "yes" : input.Text)); accept.Background = GalleryControl.Accent; accept.Foreground = Brushes.White; actions.Children.Add(accept); stack.Children.Add(actions); dialog.Content = stack;
        dialog.Opened += (_, _) => { if (!confirmation) { input.Focus(); input.SelectAll(); } };
        input.KeyDown += (_, e) => { if (e.Key == Key.Enter) dialog.Close(input.Text); };
        return await dialog.ShowDialog<string?>(this);
    }
    private async void OnClosing(object? sender, WindowClosingEventArgs e)
    {
        if (_closingReady) return; e.Cancel = true;
        if (_closingPending) return; _closingPending = true;
        try
        {
            SaveTags(); if (WindowState == WindowState.Normal) { Library.State.Preferences.WindowWidth = Width; Library.State.Preferences.WindowHeight = Height; }
            await Library.FlushAsync(); await Placement.SaveAsync(); _closingReady = true; _settings?.Close(); Close();
        }
        catch (Exception error)
        {
            Library.Report("Some changes could not be saved: " + error.Message);
            if (await PromptAsync("Unsaved changes", "Some changes could not be saved. Keep Rose open to try again, or quit without saving the pending edits.\n\n" + error.Message, "Quit without saving", confirmation: true) is not null)
            { _closingReady = true; _settings?.Close(); Close(); }
        }
        finally { _closingPending = false; }
    }
    public void DisposeResources()
    {
        if (_isDisposed) return; _isDisposed = true; _searchDelay.Stop();
        _previewCancellation?.Cancel(); _viewerCancellation?.Cancel();
        Placement.Dispose();
        _preview.Source = null; _previewBitmap?.Dispose(); Gallery.Dispose(); Viewport.Dispose(); _thumbnails.Dispose(); Library.Dispose();
    }
}
