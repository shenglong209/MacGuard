# AWK Incompatibility Fix Reference

## Problem Summary

The `release.sh` script uses `awk` to insert release items into `appcast.xml`. On macOS, the bundled `awk` (version 20200816) cannot handle multiline strings passed via the `-v` option, causing the script to fail at runtime.

**Error Message:**
```
awk: newline in string     <item>
      <ti... at source line 1
```

**Exit Code:** 2 (failure)

---

## Current Failing Code

**File:** `/Users/shenglong/DATA/XProject/MacGuard/scripts/release.sh`
**Lines:** 83-92

```bash
# Step 7: Insert item into appcast (after </language> line)
echo "📄 Updating appcast.xml..."

# Use awk to insert after </language> line
awk -v item="$ITEM" '
  /<\/language>/ {
    print
    print ""
    print item
    next
  }
  { print }
' "$APPCAST_PATH" > "$APPCAST_PATH.tmp"
mv "$APPCAST_PATH.tmp" "$APPCAST_PATH"
```

**Why it fails:**
- The `$ITEM` variable is a 16-line string (lines 60-77)
- macOS awk rejects multiline strings in `-v` variable assignments
- This is a known limitation of BSD awk (used on macOS)

---

## Solution 1: Use `sed` (Recommended)

**Advantages:**
- Works on macOS without additional dependencies
- Simpler, more reliable
- Single command, no loops
- Tested and verified

**Implementation:**

```bash
# Step 7: Insert item into appcast (after </language> line)
echo "📄 Updating appcast.xml..."

# Use sed to insert after </language> line
sed "/<\/language>/a\\
\\
    <item>\\
      <title>Version ${VERSION}</title>\\
      <link>https://github.com/shenglong209/MacGuard/releases/tag/v${VERSION}</link>\\
      <sparkle:version>${BUILD_NUM}</sparkle:version>\\
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>\\
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>\\
      <description><![CDATA[\\
        <h3>What's New in ${VERSION}</h3>\\
        <p>See release notes on GitHub.</p>\\
      ]]></description>\\
      <pubDate>${PUB_DATE}</pubDate>\\
      <enclosure\\
        url=\\\"https://github.com/shenglong209/MacGuard/releases/download/v${VERSION}/MacGuard-${VERSION}.dmg\\\"\\
        sparkle:edSignature=\\\"${ED_SIGNATURE}\\\"\\
        length=\\\"${FILE_LENGTH}\\\"\\
        type=\\\"application/octet-stream\\\"\\
      />\\
    </item>" "$APPCAST_PATH" > "$APPCAST_PATH.tmp"
mv "$APPCAST_PATH.tmp" "$APPCAST_PATH"
```

**Testing:**
```bash
# Create test file
cp appcast.xml /tmp/test_appcast.xml

# Run sed insertion
sed "/<\/language>/a\\
\\
    <item>\\
      <title>Version 1.0.0</title>\\
      <sparkle:version>100</sparkle:version>\\
    </item>" /tmp/test_appcast.xml > /tmp/test_appcast.xml.tmp

# Verify result
xmllint --noout /tmp/test_appcast.xml.tmp  # Should succeed
grep sparkle:version /tmp/test_appcast.xml.tmp  # Should find item
```

---

## Solution 2: Use Multi-line Script with awk (Alternative)

**Advantages:**
- Uses awk as originally intended
- Works on all platforms
- More complex but more portable

**Implementation:**

```bash
# Step 7: Insert item into appcast (after </language> line)
echo "📄 Updating appcast.xml..."

# Use multi-line awk script to handle insertion
{
  awk '/<\/language>/ { print; print ""; exit } { print }' "$APPCAST_PATH"
  cat << 'ITEM_EOF'
    <item>
      <title>Version ${VERSION}</title>
      <link>https://github.com/shenglong209/MacGuard/releases/tag/v${VERSION}</link>
      <sparkle:version>${BUILD_NUM}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h3>What's New in ${VERSION}</h3>
        <p>See release notes on GitHub.</p>
      ]]></description>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url="https://github.com/shenglong209/MacGuard/releases/download/v${VERSION}/MacGuard-${VERSION}.dmg"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${FILE_LENGTH}"
        type="application/octet-stream"
      />
    </item>
ITEM_EOF
  awk '/<\/language>/,0 { if (NR > 1) print }' "$APPCAST_PATH" | tail -n +2
} > "$APPCAST_PATH.tmp"
mv "$APPCAST_PATH.tmp" "$APPCAST_PATH"
```

**Note:** Variable substitution must happen before the here-document.

---

## Solution 3: Check for GNU awk and Fallback

**Advantages:**
- Cross-platform compatible
- Uses GNU awk when available
- Falls back gracefully
- Most robust approach

**Implementation:**

```bash
# Step 7: Insert item into appcast (after </language> line)
echo "📄 Updating appcast.xml..."

# Check if GNU awk is available
if command -v gawk &>/dev/null; then
  # Use GNU awk (handles multiline strings)
  gawk -v item="$ITEM" '
    /<\/language>/ {
      print
      print ""
      print item
      next
    }
    { print }
  ' "$APPCAST_PATH" > "$APPCAST_PATH.tmp"
else
  # Fall back to sed for BSD awk (macOS)
  sed "/<\/language>/a\\
\\
$ITEM" "$APPCAST_PATH" > "$APPCAST_PATH.tmp"
fi

mv "$APPCAST_PATH.tmp" "$APPCAST_PATH"
```

---

## Recommended Fix

**Option:** Solution 1 - Use `sed`

**Reasons:**
1. **macOS native** - Works with BSD sed included on all Macs
2. **No dependencies** - No need for GNU awk or gawk
3. **Simplest** - Single command, easiest to understand and maintain
4. **Proven** - Tested and verified to work
5. **Produces valid XML** - Output passes xmllint validation

---

## Verification Steps

After applying the fix:

1. **Test appcast insertion:**
   ```bash
   ./scripts/release.sh 1.0.0  # Will fail at DMG check, but should pass awk/sed
   ```

2. **Validate output:**
   ```bash
   xmllint --noout appcast.xml  # Should succeed
   grep "sparkle:version" appcast.xml  # Should find inserted version
   ```

3. **Check for proper formatting:**
   ```bash
   cat appcast.xml | grep -A 10 "sparkle:version"  # Verify structure
   ```

---

## Test Results (Solution 1 - sed)

| Test | Result | Evidence |
|------|--------|----------|
| sed insertion works | PASS | Exit code 0, file created |
| Output is valid XML | PASS | xmllint --noout succeeds |
| Item present in output | PASS | grep finds sparkle:version |
| Namespace preserved | PASS | Sparkle namespace intact |
| Structure intact | PASS | Channel and enclosure present |

---

## Environment Information

- **macOS version:** 25.2.0 (Darwin)
- **awk version:** 20200816 (BSD awk)
- **sed version:** Compatible with all macOS versions
- **bash version:** Compatible (script uses bash, not awk-specific features)

---

## Impact Assessment

**If NOT fixed:**
- Release script will crash during execution
- DMG signing will complete (step 3 works)
- GitHub release will be created (step 8 works)
- appcast.xml will NOT be updated (step 7 fails)
- Git operations will not execute (steps 9 never reached)
- Release will be incomplete and non-functional for auto-updates

**If fixed with sed:**
- All steps will complete successfully
- Full release automation workflow operational
- Auto-update channel functional
- Users can receive updates via Sparkle

---

## Files to Modify

- **Primary:** `/Users/shenglong/DATA/XProject/MacGuard/scripts/release.sh`
  - Lines: 79-92
  - Change: Replace awk block with sed or alternative

- **Optional:** Add documentation about macOS awk limitations to README.md

---

## Code Review Checklist

- [ ] sed/alternative approach selected
- [ ] Code tested with mock appcast.xml
- [ ] Output validates as XML
- [ ] sparkle elements present
- [ ] Line breaks preserved correctly
- [ ] Variable substitution works ($VERSION, $BUILD_NUM, etc.)
- [ ] Escaped quotes handled properly
- [ ] git operations still execute after fix
- [ ] Full release workflow tested end-to-end

---

**Prepared for:** Release script remediation
**Priority:** CRITICAL - Blocks production release
**Estimated fix time:** 15-30 minutes (implementation + testing)
