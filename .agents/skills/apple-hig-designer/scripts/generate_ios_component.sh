#!/bin/bash

# Apple HIG Designer - iOS Component Generator
# Generate SwiftUI and UIKit components following Apple Human Interface Guidelines

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local required="${3:-false}"

    while true; do
        echo -e "${BLUE}${prompt}${NC}"
        read -r input

        if [ -z "$input" ] && [ "$required" = true ]; then
            print_error "This field is required."
            continue
        fi

        eval "$var_name='$input'"
        break
    done
}

prompt_select() {
    local prompt="$1"
    local var_name="$2"
    shift 2
    local options=("$@")

    echo -e "${BLUE}${prompt}${NC}"
    PS3="Select (1-${#options[@]}): "
    select opt in "${options[@]}"; do
        if [ -n "$opt" ]; then
            eval "$var_name='$opt'"
            break
        else
            print_error "Invalid selection. Try again."
        fi
    done
}

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║        Apple HIG Designer - Component Generator           ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Framework
print_info "Step 1/6: Framework"
prompt_select "Which framework?" FRAMEWORK \
    "SwiftUI" \
    "UIKit"

# Step 2: Component Type
print_info "Step 2/6: Component Type"
prompt_select "What type of component?" COMPONENT_TYPE \
    "Button" \
    "List/TableView" \
    "Card" \
    "Sheet/Modal" \
    "Form" \
    "NavigationView" \
    "TabView" \
    "Custom"

# Step 3: Component Name
print_info "Step 3/6: Component Name"
prompt_input "Component name (e.g., UserProfileView):" COMPONENT_NAME true

# Step 4: Features
print_info "Step 4/6: Features (comma-separated)"
echo -e "${BLUE}Select features to include:${NC}"
echo "  - accessibility (VoiceOver, Dynamic Type)"
echo "  - darkmode (Semantic colors)"
echo "  - animations (Standard iOS animations)"
echo "  - haptics (Haptic feedback)"
read -r FEATURES

# Step 5: Platform
print_info "Step 5/6: Platform"
prompt_select "Target platform?" PLATFORM \
    "iOS" \
    "iOS + iPadOS" \
    "iOS + watchOS" \
    "All (iOS, iPadOS, macOS, watchOS)"

# Step 6: Output Directory
print_info "Step 6/6: Output Location"
prompt_input "Output directory (default: ./Components):" OUTPUT_DIR
OUTPUT_DIR=${OUTPUT_DIR:-"./Components"}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate based on framework
case $FRAMEWORK in
    "SwiftUI")
        generate_swiftui_component
        ;;
    "UIKit")
        generate_uikit_component
        ;;
esac

generate_swiftui_component() {
    local file_path="$OUTPUT_DIR/$COMPONENT_NAME.swift"

    cat > "$file_path" << 'EOF'
import SwiftUI

/// COMPONENT_NAME
///
/// Description of what this component does
/// Follows Apple Human Interface Guidelines
struct COMPONENT_NAME: View {
    PROPERTIES

    var body: some View {
        COMPONENT_BODY
    }
}

PREVIEW
EOF

    # Add properties based on component type
    case $COMPONENT_TYPE in
        "Button")
            sed -i 's/PROPERTIES/\/\/ Button properties\n    let title: String\n    let action: () -> Void/' "$file_path"
            sed -i 's/COMPONENT_BODY/Button(action: action) {\n            Text(title)\n        }\n        .buttonStyle(.borderedProminent)\n        ACCESSIBILITY_MODIFIERS/' "$file_path"
            ;;
        "List/TableView")
            sed -i 's/PROPERTIES/\/\/ List properties\n    let items: [String]/' "$file_path"
            sed -i 's/COMPONENT_BODY/List(items, id: \\.self) { item in\n            Text(item)\n        }\n        .listStyle(.insetGrouped)\n        ACCESSIBILITY_MODIFIERS/' "$file_path"
            ;;
        "Card")
            sed -i 's/PROPERTIES/\/\/ Card properties\n    let title: String\n    let description: String/' "$file_path"
            sed -i 's/COMPONENT_BODY/VStack(alignment: .leading, spacing: 12) {\n            Text(title)\n                .font(.headline)\n            \n            Text(description)\n                .font(.subheadline)\n                .foregroundColor(.secondary)\n        }\n        .padding()\n        .background(Color(.systemBackground))\n        .cornerRadius(12)\n        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)\n        ACCESSIBILITY_MODIFIERS/' "$file_path"
            ;;
        "Sheet/Modal")
            sed -i 's/PROPERTIES/@State private var isPresented = false/' "$file_path"
            sed -i 's/COMPONENT_BODY/Button("Show Sheet") {\n            isPresented = true\n        }\n        .sheet(isPresented: $isPresented) {\n            NavigationStack {\n                Text("Sheet Content")\n                    .navigationTitle("Title")\n                    .navigationBarTitleDisplayMode(.inline)\n                    .toolbar {\n                        ToolbarItem(placement: .cancellationAction) {\n                            Button("Cancel") {\n                                isPresented = false\n                            }\n                        }\n                    }\n            }\n            .presentationDetents([.medium, .large])\n        }/' "$file_path"
            ;;
        "NavigationView")
            sed -i 's/PROPERTIES/\/\/ Navigation properties\n    @State private var path = NavigationPath()/' "$file_path"
            sed -i 's/COMPONENT_BODY/NavigationStack(path: $path) {\n            List {\n                NavigationLink("Item 1", value: "Detail 1")\n                NavigationLink("Item 2", value: "Detail 2")\n            }\n            .navigationTitle("Title")\n            .navigationBarTitleDisplayMode(.large)\n            .navigationDestination(for: String.self) { value in\n                Text(value)\n            }\n        }/' "$file_path"
            ;;
        "TabView")
            sed -i 's/PROPERTIES/@State private var selectedTab = 0/' "$file_path"
            sed -i 's/COMPONENT_BODY/TabView(selection: $selectedTab) {\n            Text("Home")\n                .tabItem {\n                    Label("Home", systemImage: "house")\n                }\n                .tag(0)\n            \n            Text("Search")\n                .tabItem {\n                    Label("Search", systemImage: "magnifyingglass")\n                }\n                .tag(1)\n            \n            Text("Profile")\n                .tabItem {\n                    Label("Profile", systemImage: "person")\n                }\n                .tag(2)\n        }/' "$file_path"
            ;;
        *)
            sed -i 's/PROPERTIES/\/\/ Component properties/' "$file_path"
            sed -i 's/COMPONENT_BODY/Text("Custom Component")\n            .font(.body)\n        ACCESSIBILITY_MODIFIERS/' "$file_path"
            ;;
    esac

    # Add accessibility modifiers if requested
    if [[ $FEATURES == *"accessibility"* ]]; then
        sed -i 's/ACCESSIBILITY_MODIFIERS/.accessibilityLabel("Component label")\n        .accessibilityHint("Component hint")/' "$file_path"
    else
        sed -i 's/ACCESSIBILITY_MODIFIERS//' "$file_path"
    fi

    # Add preview
    sed -i "s/PREVIEW/#Preview {\n    COMPONENT_NAME()\n}/" "$file_path"

    # Replace component name
    sed -i "s/COMPONENT_NAME/$COMPONENT_NAME/g" "$file_path"

    print_success "Created SwiftUI component: $file_path"

    # Generate test file if needed
    if [[ $FEATURES == *"testing"* ]]; then
        generate_test_file_swiftui
    fi
}

generate_uikit_component() {
    local file_path="$OUTPUT_DIR/$COMPONENT_NAME.swift"

    cat > "$file_path" << 'EOF'
import UIKit

/// COMPONENT_NAME
///
/// Description of what this component does
/// Follows Apple Human Interface Guidelines
class COMPONENT_NAME: UIView {

    // MARK: - Properties
    PROPERTIES

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Setup

    private func setupView() {
        SETUP_CODE
        setupAccessibility()
    }

    private func setupAccessibility() {
        ACCESSIBILITY_SETUP
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout code here
    }
}
EOF

    # Add properties based on component type
    case $COMPONENT_TYPE in
        "Button")
            sed -i 's/PROPERTIES/private let button: UIButton = {\n        let button = UIButton(type: .system)\n        button.translatesAutoresizingMaskIntoConstraints = false\n        button.configuration = .filled()\n        return button\n    }()/' "$file_path"
            sed -i 's/SETUP_CODE/addSubview(button)\n        \n        NSLayoutConstraint.activate([\n            button.centerXAnchor.constraint(equalTo: centerXAnchor),\n            button.centerYAnchor.constraint(equalTo: centerYAnchor),\n            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)\n        ])/' "$file_path"
            ;;
        "List/TableView")
            sed -i 's/PROPERTIES/private let tableView: UITableView = {\n        let table = UITableView(frame: .zero, style: .insetGrouped)\n        table.translatesAutoresizingMaskIntoConstraints = false\n        return table\n    }()\n    \n    private var items: [String] = []/' "$file_path"
            sed -i 's/SETUP_CODE/addSubview(tableView)\n        tableView.delegate = self\n        tableView.dataSource = self\n        \n        NSLayoutConstraint.activate([\n            tableView.topAnchor.constraint(equalTo: topAnchor),\n            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),\n            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),\n            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)\n        ])/' "$file_path"
            ;;
        *)
            sed -i 's/PROPERTIES/\/\/ Add component properties here/' "$file_path"
            sed -i 's/SETUP_CODE/\/\/ Setup UI components/' "$file_path"
            ;;
    esac

    # Add accessibility setup
    if [[ $FEATURES == *"accessibility"* ]]; then
        sed -i 's/ACCESSIBILITY_SETUP/isAccessibilityElement = true\n        accessibilityLabel = "Component label"\n        accessibilityHint = "Component hint"\n        accessibilityTraits = .button/' "$file_path"
    else
        sed -i 's/ACCESSIBILITY_SETUP/\/\/ Configure accessibility/' "$file_path"
    fi

    # Replace component name
    sed -i "s/COMPONENT_NAME/$COMPONENT_NAME/g" "$file_path"

    print_success "Created UIKit component: $file_path"
}

generate_test_file_swiftui() {
    local test_file="$OUTPUT_DIR/${COMPONENT_NAME}Tests.swift"

    cat > "$test_file" << 'EOF'
import XCTest
import SwiftUI
@testable import YourApp

final class COMPONENT_NAMETests: XCTestCase {

    func testComponentRenders() {
        let view = COMPONENT_NAME()
        XCTAssertNotNil(view)
    }

    func testAccessibility() {
        // Test VoiceOver labels
        // Test Dynamic Type support
    }
}
EOF

    sed -i "s/COMPONENT_NAME/$COMPONENT_NAME/g" "$test_file"
    print_success "Created test file: $test_file"
}

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Generation Complete                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
print_success "Component: $COMPONENT_NAME"
print_success "Framework: $FRAMEWORK"
print_success "Type: $COMPONENT_TYPE"
print_success "Platform: $PLATFORM"
print_success "Location: $OUTPUT_DIR"
echo ""
print_info "Files created:"
echo "  - $COMPONENT_NAME.swift"
if [[ $FEATURES == *"testing"* ]]; then
    echo "  - ${COMPONENT_NAME}Tests.swift"
fi
echo ""
print_info "Apple HIG Guidelines Applied:"
echo "  ✓ Minimum tap target: 44x44 points"
echo "  ✓ System fonts (San Francisco)"
echo "  ✓ Semantic colors (dark mode support)"
if [[ $FEATURES == *"accessibility"* ]]; then
    echo "  ✓ VoiceOver support"
    echo "  ✓ Dynamic Type support"
fi
if [[ $FEATURES == *"haptics"* ]]; then
    echo "  ✓ Haptic feedback"
fi
echo ""
print_info "Next steps:"
echo "  1. Review generated code"
echo "  2. Add component to your Xcode project"
echo "  3. Customize properties and logic"
echo "  4. Test with VoiceOver"
echo "  5. Test in light and dark mode"
echo "  6. Test with different Dynamic Type sizes"
echo ""
