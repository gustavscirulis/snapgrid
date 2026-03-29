#!/bin/bash

# Apple HIG Designer - Design Validation
# Validate Swift code against Apple Human Interface Guidelines

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARNING_COUNT=0

# Helper functions
print_success() {
    echo -e "${GREEN}✓ PASS${NC} $1"
    ((PASS_COUNT++))
}

print_error() {
    echo -e "${RED}✗ FAIL${NC} $1"
    ((FAIL_COUNT++))
}

print_warning() {
    echo -e "${YELLOW}⚠ WARN${NC} $1"
    ((WARNING_COUNT++))
}

print_info() {
    echo -e "${BLUE}ℹ INFO${NC} $1"
}

print_section() {
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}$1${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║         Apple HIG Designer - Design Validation            ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Get target
if [ -z "$1" ]; then
    print_info "Usage: $0 <file.swift|directory>"
    print_info "Example: $0 ContentView.swift"
    print_info "Example: $0 Views/"
    exit 1
fi

TARGET="$1"

# Check if target exists
if [ ! -e "$TARGET" ]; then
    print_error "Target not found: $TARGET"
    exit 1
fi

# Section 1: Typography
print_section "1. TYPOGRAPHY"

check_system_fonts() {
    # Check for system font usage
    if grep -q '\.font(' "$1"; then
        if grep -q '\.font(.body)\|\.font(.title)\|\.font(.headline)' "$1"; then
            print_success "Using system text styles (Dynamic Type)"
        else
            print_warning "Consider using system text styles (.body, .headline, etc.)"
        fi
    fi

    # Check for hard-coded font sizes
    if grep -q 'Font.system(size:' "$1"; then
        print_warning "Hard-coded font sizes found - consider Dynamic Type"
        echo "         Tip: Use .font(.body) instead of .font(.system(size: 17))"
    fi
}

# Section 2: Colors
print_section "2. COLORS & DARK MODE"

check_semantic_colors() {
    # Check for semantic color usage
    if grep -q 'Color(.label)\|Color(.systemBackground)\|Color(.secondary)' "$1"; then
        print_success "Using semantic colors (dark mode support)"
    else
        if grep -q 'Color(' "$1"; then
            print_warning "Consider using semantic colors for dark mode support"
            echo "         Use: Color(.label) instead of Color.black"
        fi
    fi

    # Check for hard-coded colors
    if grep -q '#[0-9A-Fa-f]\{6\}\|Color.black\|Color.white' "$1"; then
        print_error "Hard-coded colors found - use semantic colors"
        echo "         Fix: Use Color(.label), Color(.systemBackground), etc."
    fi
}

# Section 3: Accessibility
print_section "3. ACCESSIBILITY"

check_accessibility_labels() {
    # Check for accessibility labels
    if grep -q 'Image(systemName:' "$1"; then
        if grep -q '\.accessibilityLabel' "$1"; then
            print_success "SF Symbols have accessibility labels"
        else
            print_error "SF Symbols missing accessibility labels"
            echo "         Fix: Add .accessibilityLabel(\"Description\")"
        fi
    fi

    # Check for VoiceOver support
    if grep -q '\.accessibilityLabel\|\.accessibilityHint\|\.accessibilityValue' "$1"; then
        print_success "VoiceOver support implemented"
    else
        print_warning "Consider adding VoiceOver support"
    fi
}

# Section 4: Touch Targets
print_section "4. TOUCH TARGETS"

check_touch_targets() {
    # Check for minimum tap targets
    if grep -q '\.frame(.*height.*44\|minHeight.*44' "$1"; then
        print_success "Minimum touch target size (44pt) specified"
    else
        if grep -q 'Button\|.onTapGesture' "$1"; then
            print_warning "Verify touch targets are at least 44x44 points"
            echo "         Tip: .frame(minWidth: 44, minHeight: 44)"
        fi
    fi
}

# Section 5: Spacing
print_section "5. SPACING & LAYOUT"

check_spacing() {
    # Check for 8pt grid usage
    if grep -q '\.padding([0-9]*)\|\.spacing([0-9]*)' "$1"; then
        # Extract padding values
        paddings=$(grep -o '\.padding([0-9]*)' "$1" | grep -o '[0-9]*')
        invalid=false
        for pad in $paddings; do
            if [ $((pad % 8)) -ne 0 ]; then
                invalid=true
                break
            fi
        done

        if [ "$invalid" = false ]; then
            print_success "Following 8pt grid system"
        else
            print_warning "Consider using 8pt grid (8, 16, 24, 32, etc.)"
        fi
    fi

    # Check for safe area usage
    if grep -q '\.ignoresSafeArea' "$1"; then
        print_warning "Ignoring safe areas - ensure intentional"
        echo "         Tip: Respect safe areas for better device compatibility"
    fi
}

# Section 6: Navigation
print_section "6. NAVIGATION"

check_navigation() {
    # Check for navigation best practices
    if grep -q 'NavigationStack\|NavigationView' "$1"; then
        if grep -q '\.navigationTitle' "$1"; then
            print_success "Navigation titles present"
        else
            print_error "NavigationStack missing .navigationTitle"
        fi

        # Check for navigation bar mode
        if grep -q '\.navigationBarTitleDisplayMode(.large)' "$1"; then
            print_success "Using large titles for top-level views"
        fi
    fi

    # Check for TabView
    if grep -q 'TabView' "$1"; then
        # Count tabItems
        tab_count=$(grep -c '\.tabItem' "$1")
        if [ "$tab_count" -ge 3 ] && [ "$tab_count" -le 5 ]; then
            print_success "TabView has appropriate number of tabs ($tab_count)"
        elif [ "$tab_count" -gt 5 ]; then
            print_error "Too many tabs ($tab_count) - maximum 5 recommended"
        elif [ "$tab_count" -lt 3 ]; then
            print_warning "Consider if TabView is appropriate for $tab_count tabs"
        fi
    fi
}

# Section 7: Buttons
print_section "7. BUTTONS & CONTROLS"

check_buttons() {
    # Check for button styles
    if grep -q 'Button(' "$1"; then
        if grep -q '\.buttonStyle' "$1"; then
            print_success "Using button styles"

            # Check for button hierarchy
            if grep -q '\.buttonStyle(.borderedProminent)' "$1"; then
                prominent_count=$(grep -c '\.buttonStyle(.borderedProminent)' "$1")
                if [ "$prominent_count" -eq 1 ]; then
                    print_success "Single prominent button (good hierarchy)"
                else
                    print_warning "Multiple prominent buttons - ensure clear hierarchy"
                fi
            fi
        else
            print_warning "Consider using .buttonStyle for consistent appearance"
        fi

        # Check button labels
        if grep -q 'Button("' "$1"; then
            # Extract button texts
            if grep -q 'Button("[A-Z]' "$1"; then
                print_success "Button labels start with capital letters"
            fi
        fi
    fi
}

# Section 8: Lists
print_section "8. LISTS & TABLES"

check_lists() {
    # Check for list styles
    if grep -q 'List' "$1"; then
        if grep -q '\.listStyle' "$1"; then
            if grep -q '\.listStyle(.insetGrouped)' "$1"; then
                print_success "Using iOS standard .insetGrouped list style"
            fi
        else
            print_warning "Consider specifying .listStyle(.insetGrouped)"
        fi
    fi
}

# Section 9: Animations
print_section "9. ANIMATIONS & MOTION"

check_animations() {
    # Check for spring animations
    if grep -q 'withAnimation' "$1"; then
        if grep -q '\.spring()\|\.easeInOut' "$1"; then
            print_success "Using iOS-style animations"
        fi
    fi

    # Check for reduce motion
    if grep -q '@Environment(.*accessibilityReduceMotion)' "$1"; then
        print_success "Respecting Reduce Motion preference"
    else
        if grep -q 'withAnimation\|\.animation' "$1"; then
            print_warning "Consider respecting Reduce Motion accessibility setting"
            echo "         Tip: @Environment(\\.accessibilityReduceMotion) var reduceMotion"
        fi
    fi
}

# Section 10: SF Symbols
print_section "10. SF SYMBOLS"

check_sf_symbols() {
    # Check for SF Symbols usage
    if grep -q 'Image(systemName:' "$1"; then
        print_success "Using SF Symbols"

        # Check for proper sizing
        if grep -q '\.font(.title)\|\.imageScale' "$1"; then
            print_success "SF Symbols are properly sized"
        else
            print_warning "Consider sizing SF Symbols with .font() or .imageScale()"
        fi
    fi

    # Check for custom images that should be SF Symbols
    common_icons="heart|star|person|home|settings|search|share"
    if grep -E "Image\\(\"($common_icons)" "$1"; then
        print_warning "Consider using SF Symbols instead of custom icons"
    fi
}

# Run checks on files
if [ -f "$TARGET" ]; then
    # Single file
    if [[ "$TARGET" == *.swift ]]; then
        check_system_fonts "$TARGET"
        check_semantic_colors "$TARGET"
        check_accessibility_labels "$TARGET"
        check_touch_targets "$TARGET"
        check_spacing "$TARGET"
        check_navigation "$TARGET"
        check_buttons "$TARGET"
        check_lists "$TARGET"
        check_animations "$TARGET"
        check_sf_symbols "$TARGET"
    else
        print_error "File is not a Swift file: $TARGET"
        exit 1
    fi
elif [ -d "$TARGET" ]; then
    # Directory - find Swift files
    swift_files=$(find "$TARGET" -name "*.swift" 2>/dev/null)

    if [ -z "$swift_files" ]; then
        print_error "No Swift files found in $TARGET"
        exit 1
    fi

    for file in $swift_files; do
        print_info "Checking: $file"
        check_system_fonts "$file"
        check_semantic_colors "$file"
        check_accessibility_labels "$file"
        check_touch_targets "$file"
        check_spacing "$file"
        echo ""
    done
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Validation Summary                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✓ Passed:   $PASS_COUNT${NC}"
echo -e "${RED}✗ Failed:   $FAIL_COUNT${NC}"
echo -e "${YELLOW}⚠ Warnings: $WARNING_COUNT${NC}"
echo ""

# Calculate score
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ $TOTAL -gt 0 ]; then
    SCORE=$(( (PASS_COUNT * 100) / TOTAL ))
    echo "HIG Compliance Score: $SCORE%"
    echo ""

    if [ $SCORE -ge 90 ]; then
        echo -e "${GREEN}Excellent! Your design follows Apple HIG.${NC}"
    elif [ $SCORE -ge 70 ]; then
        echo -e "${YELLOW}Good, but needs improvements.${NC}"
    else
        echo -e "${RED}Needs significant improvements to match Apple HIG.${NC}"
    fi
fi

echo ""
print_info "Apple HIG Recommendations:"
echo "  1. Use system fonts with Dynamic Type"
echo "  2. Use semantic colors for dark mode"
echo "  3. Add VoiceOver labels to all images"
echo "  4. Ensure 44x44pt minimum touch targets"
echo "  5. Follow 8pt grid system"
echo "  6. Use large titles for top-level navigation"
echo "  7. Limit TabView to 3-5 tabs"
echo "  8. Use .borderedProminent for primary actions only"
echo ""
print_info "Resources:"
echo "  - Apple HIG: https://developer.apple.com/design/human-interface-guidelines/"
echo "  - SF Symbols: https://developer.apple.com/sf-symbols/"
echo "  - WWDC Videos: https://developer.apple.com/videos/"
echo ""

# Exit code based on failures
if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi
