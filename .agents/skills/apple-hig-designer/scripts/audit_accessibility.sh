#!/bin/bash

# Apple HIG Designer - iOS Accessibility Audit
# Check iOS app accessibility compliance (VoiceOver, Dynamic Type, etc.)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARNING_COUNT=0

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

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║      Apple HIG Designer - Accessibility Audit             ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ -z "$1" ]; then
    print_info "Usage: $0 <file.swift|directory>"
    exit 1
fi

TARGET="$1"

if [ ! -e "$TARGET" ]; then
    print_error "Target not found: $TARGET"
    exit 1
fi

# VoiceOver Support
print_section "1. VOICEOVER SUPPORT"

check_voiceover() {
    if grep -q 'Image(systemName:' "$1"; then
        if grep -q '\.accessibilityLabel' "$1"; then
            print_success "Images have accessibility labels"
        else
            print_error "Images missing accessibility labels"
            echo "         Fix: .accessibilityLabel(\"Description\")"
        fi
    fi

    if grep -q '\.accessibilityHint' "$1"; then
        print_success "Accessibility hints provided"
    fi

    if grep -q '\.accessibilityElement(children: .combine)' "$1"; then
        print_success "Grouping accessibility elements"
    fi
}

# Dynamic Type
print_section "2. DYNAMIC TYPE"

check_dynamic_type() {
    if grep -q '\.font(.body)\|\.font(.headline)\|\.font(.title)' "$1"; then
        print_success "Using system text styles (Dynamic Type supported)"
    else
        print_error "Not using system text styles"
        echo "         Fix: Use .font(.body) instead of .font(.system(size: 17))"
    fi

    if grep -q '\.font(.custom(' "$1"; then
        if grep -q 'relativeTo:' "$1"; then
            print_success "Custom fonts support Dynamic Type"
        else
            print_error "Custom fonts don't support Dynamic Type"
            echo "         Fix: .font(.custom(\"Font\", size: 17, relativeTo: .body))"
        fi
    fi
}

# Color Contrast
print_section "3. COLOR CONTRAST"

check_color_contrast() {
    if grep -q 'Color(.label)\|Color(.secondaryLabel)' "$1"; then
        print_success "Using semantic text colors (good contrast)"
    else
        print_warning "Verify color contrast ratios (4.5:1 minimum)"
    fi

    if grep -q '@Environment(.*colorSchemeContrast)' "$1"; then
        print_success "Supporting Increase Contrast mode"
    else
        print_warning "Consider supporting Increase Contrast"
        echo "         Tip: @Environment(\\.colorSchemeContrast) var contrast"
    fi
}

# Reduce Motion
print_section "4. REDUCE MOTION"

check_reduce_motion() {
    if grep -q '@Environment(.*accessibilityReduceMotion)' "$1"; then
        print_success "Respecting Reduce Motion preference"
    else
        if grep -q 'withAnimation\|\.animation' "$1"; then
            print_error "Animations present but not respecting Reduce Motion"
            echo "         Fix: @Environment(\\.accessibilityReduceMotion) var reduceMotion"
        fi
    fi
}

# Touch Targets
print_section "5. TOUCH TARGETS"

check_touch_targets() {
    if grep -q '\.frame.*minHeight.*44\|height.*44' "$1"; then
        print_success "Minimum touch target (44pt) specified"
    else
        if grep -q 'Button\|.onTapGesture' "$1"; then
            print_error "Touch targets may be too small"
            echo "         Fix: .frame(minWidth: 44, minHeight: 44)"
        fi
    fi
}

# Run checks
if [ -f "$TARGET" ]; then
    if [[ "$TARGET" == *.swift ]]; then
        check_voiceover "$TARGET"
        check_dynamic_type "$TARGET"
        check_color_contrast "$TARGET"
        check_reduce_motion "$TARGET"
        check_touch_targets "$TARGET"
    fi
elif [ -d "$TARGET" ]; then
    swift_files=$(find "$TARGET" -name "*.swift" 2>/dev/null)
    for file in $swift_files; do
        print_info "Checking: $file"
        check_voiceover "$file"
        check_dynamic_type "$file"
        check_color_contrast "$file"
        check_reduce_motion "$file"
        check_touch_targets "$file"
        echo ""
    done
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                 Accessibility Summary                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✓ Passed:   $PASS_COUNT${NC}"
echo -e "${RED}✗ Failed:   $FAIL_COUNT${NC}"
echo -e "${YELLOW}⚠ Warnings: $WARNING_COUNT${NC}"
echo ""

TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ $TOTAL -gt 0 ]; then
    SCORE=$(( (PASS_COUNT * 100) / TOTAL ))
    echo "Accessibility Score: $SCORE%"
    echo ""
fi

echo ""
print_info "Testing Recommendations:"
echo "  1. Test with VoiceOver enabled (Settings > Accessibility > VoiceOver)"
echo "  2. Test with largest Dynamic Type size"
echo "  3. Test with Increase Contrast enabled"
echo "  4. Test with Reduce Motion enabled"
echo "  5. Test with Reduce Transparency enabled"
echo "  6. Use Accessibility Inspector in Xcode"
echo ""
print_info "Resources:"
echo "  - Accessibility Inspector: Xcode > Open Developer Tool"
echo "  - Apple Accessibility: https://www.apple.com/accessibility/"
echo ""

[ $FAIL_COUNT -gt 0 ] && exit 1 || exit 0
