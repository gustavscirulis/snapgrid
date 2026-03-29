# iOS Components Catalog

Complete reference for native iOS UI components following Apple Human Interface Guidelines.

## Navigation Components

### Navigation Bar

Top bar for hierarchical navigation.

```swift
NavigationStack {
    List {
        Text("Item 1")
        Text("Item 2")
    }
    .navigationTitle("Title")
    .navigationBarTitleDisplayMode(.large) // or .inline
    .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Add") {
                // Action
            }
        }
    }
}
```

**Guidelines:**
- Use `.large` for top-level views
- Use `.inline` for detail views
- Maximum 2-3 toolbar items
- Keep actions relevant to context

### Tab Bar

Bottom navigation for peer destinations.

```swift
TabView {
    HomeView()
        .tabItem {
            Label("Home", systemImage: "house")
        }

    SearchView()
        .tabItem {
            Label("Search", systemImage: "magnifyingglass")
        }
}
```

**Guidelines:**
- 3-5 tabs maximum
- Use SF Symbols for icons
- One-word labels
- Never hide or disable tabs

### Toolbar

Actions for current context.

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Button("Edit") { }
    }

    ToolbarItem(placement: .bottomBar) {
        Button("Delete") { }
    }
}
```

## Controls

### Button

Primary action control.

```swift
// Prominent (primary action)
Button("Continue") { }
    .buttonStyle(.borderedProminent)

// Bordered (secondary action)
Button("Cancel") { }
    .buttonStyle(.bordered)

// Plain (tertiary action)
Button("Learn More") { }
    .buttonStyle(.plain)
```

### Toggle (Switch)

Boolean control.

```swift
Toggle("Enable notifications", isOn: $isEnabled)
    .toggleStyle(.switch)
```

### Slider

Continuous value selection.

```swift
Slider(value: $volume, in: 0...100)
    .accessibilityLabel("Volume")
    .accessibilityValue("\(Int(volume))%")
```

### Picker

Selection from multiple options.

```swift
// Menu style
Picker("Size", selection: $size) {
    Text("Small").tag("S")
    Text("Medium").tag("M")
    Text("Large").tag("L")
}
.pickerStyle(.menu)

// Segmented (2-5 options)
Picker("View", selection: $viewType) {
    Text("List").tag(0)
    Text("Grid").tag(1)
}
.pickerStyle(.segmented)
```

### TextField

Text input.

```swift
TextField("Username", text: $username)
    .textFieldStyle(.roundedBorder)
    .textContentType(.username)
    .textInputAutocapitalization(.never)
    .autocorrectionDisabled()
```

### SecureField

Password input.

```swift
SecureField("Password", text: $password)
    .textFieldStyle(.roundedBorder)
    .textContentType(.password)
```

## Content Views

### List

Scrollable rows of content.

```swift
List {
    Section("Today") {
        ForEach(items) { item in
            NavigationLink {
                DetailView(item: item)
            } label: {
                HStack {
                    Image(systemName: item.icon)
                    Text(item.title)
                }
            }
        }
        .onDelete { indices in
            items.remove(atOffsets: indices)
        }
    }
}
.listStyle(.insetGrouped)
```

**List Styles:**
- `.plain` - Edge-to-edge
- `.insetGrouped` - Rounded sections (iOS default)
- `.sidebar` - Navigation sidebar

### ScrollView

Custom scrollable content.

```swift
ScrollView {
    VStack(spacing: 16) {
        ForEach(items) { item in
            CardView(item: item)
        }
    }
    .padding()
}
```

### Grid

Multi-column layout.

```swift
// LazyVGrid for vertical scrolling
LazyVGrid(columns: [
    GridItem(.adaptive(minimum: 150))
]) {
    ForEach(items) { item in
        CardView(item: item)
    }
}

// LazyHGrid for horizontal scrolling
LazyHGrid(rows: [
    GridItem(.fixed(200))
]) {
    ForEach(items) { item in
        CardView(item: item)
    }
}
```

## Presentations

### Sheet (Modal)

Present content modally.

```swift
.sheet(isPresented: $showSheet) {
    NavigationStack {
        DetailView()
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSheet = false
                    }
                }
            }
    }
    .presentationDetents([.medium, .large])
}
```

**Detents:**
- `.medium` - Half screen
- `.large` - Full screen
- Custom: `.height(400)`

### Alert

Important messages.

```swift
.alert("Delete Item?", isPresented: $showAlert) {
    Button("Delete", role: .destructive) {
        deleteItem()
    }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This action cannot be undone.")
}
```

### Confirmation Dialog

Action selection.

```swift
.confirmationDialog("Options", isPresented: $showOptions) {
    Button("Edit") { }
    Button("Share") { }
    Button("Delete", role: .destructive) { }
    Button("Cancel", role: .cancel) { }
}
```

## Indicators

### Progress View

Loading indicator.

```swift
// Indeterminate
ProgressView()

// Determinate
ProgressView(value: progress, total: 1.0)

// With label
ProgressView("Loading...") {
    // Optional current task
    Text("5 of 10 items")
}
```

### Activity Indicator

Spinning indicator.

```swift
ProgressView()
    .progressViewStyle(.circular)
    .scaleEffect(1.5)
```

## Content Containers

### Card View

Contained content block.

```swift
struct CardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Title")
                .font(.headline)

            Text("Description")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Action") { }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8)
    }
}
```

### GroupBox

Labeled group of views.

```swift
GroupBox("Settings") {
    Toggle("Notifications", isOn: $notifications)
    Toggle("Location", isOn: $location)
}
```

### Form

Settings and input grouping.

```swift
Form {
    Section("Account") {
        TextField("Username", text: $username)
        SecureField("Password", text: $password)
    }

    Section("Preferences") {
        Toggle("Notifications", isOn: $notifications)
        Picker("Theme", selection: $theme) {
            Text("Light").tag("light")
            Text("Dark").tag("dark")
        }
    }
}
```

## Best Practices

**Navigation:**
- Use NavigationStack for hierarchical
- Use TabView for flat (3-5 peers)
- Never combine TabView + Toolbar in same view

**Forms:**
- Group related inputs
- Provide clear labels
- Show validation errors inline
- Use appropriate input types

**Lists:**
- Use `.insetGrouped` style
- Support swipe actions
- Provide pull-to-refresh when relevant
- Use sections for organization

**Modals:**
- Use for focused tasks
- Provide clear dismiss action
- Don't nest modals
- Use appropriate detent

---

For more details: https://developer.apple.com/design/human-interface-guidelines/components
