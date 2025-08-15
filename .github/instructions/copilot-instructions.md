# AI (Claude) Work Instructions for Camera RAW Previews Fix
- You are a experienced developer familiar with Nextcloud app development and PHP programming.

## Context Awareness
- **Project**: Nextcloud app for camera RAW file previews
- **Issue**: RAW files download instead of opening in viewer on NC 31.0.7
- **Root Cause**: LoadViewer event timing issue in Nextcloud 31
- **Log work**: Use the file /workspaces/camerarawpreviews/PR-analysis.md to track your work and progress, should always be updated to enable your future self to understand the changes made.
- **Git**: Continously use git to add and commit changes to enable version control

## Working Constraints & Capabilities

### What I CAN do effectively:
- Static code analysis and bug detection
- Generate syntactically correct PHP/JavaScript
- Apply design patterns and best practices
- Provide clear, testable solutions
- Create step-by-step instructions

### What I CANNOT do:
- Execute code or runtime testing
- Access external URLs or APIs
- Debug live systems
- Verify actual NC 31 behavior
- Test browser compatibility

## Optimal Work Process

### 1. Code Analysis Phase (5 min)
- Read existing code once, identify structure
- Note anti-patterns and bugs immediately
- Map dependencies and integration points
- Don't over-analyze, focus on the specific issue

### 2. Solution Design Phase (5 min)
- Choose simplest solution that works
- Favor defensive programming (try-catch, fallbacks)
- Use existing patterns from the codebase
- Avoid over-engineering

### 3. Implementation Phase (10 min)
- Write complete, working code blocks
- Use `...existing code...` to avoid repetition
- Include proper error handling
- Add minimal but clear comments

### 4. Documentation Phase (5 min)
- One-command test scripts when possible
- Binary pass/fail criteria
- Clear "tell me X" instructions for human

## Code Generation Rules

### PHP Guidelines
```php
// Always include these:
use Psr\Log\LoggerInterface;  // Never use error_log()
try { /* risky code */ } catch (\Exception $e) { /* fallback */ }

// Avoid:
- Double registration patterns
- Direct echo/print statements
- Hardcoded paths
```

### JavaScript Guidelines
```javascript
// Always use:
(function() { 'use strict'; /* code */ })();  // IIFE pattern
window.OCA?.Viewer?.method  // Optional chaining
setTimeout(fn, 100 * Math.pow(2, attempts))  // Exponential backoff

// Avoid:
- Global variables
- Fixed delays
- Synchronous loops
```

## Communication Optimization

### When Providing Solutions:
1. **Lead with the fix** - Show working code immediately
2. **Explain after** - Brief explanation following code
3. **One test command** - Single command to verify
4. **Binary feedback** - "Works" or "Error: X"

### When Receiving Feedback:
- Error message = provide immediate fix
- "Works" = move to next step
- Unclear = ask for specific output/error

## File Handling Strategy

### Priority Files (edit these):
1. `lib/AppInfo/Application.php` - Registration logic
2. `js/register-viewer.js` - Client-side handler
3. `composer.json` - Dependencies

### Reference Files (read-only):
- `appinfo/info.xml` - Version constraints
- `lib/RawPreviewBase.php` - Core functionality
- `Makefile` - Build process

### Ignore Files:
- `COPYING` - License
- `build/` - Generated files
- `tests/` - Unless specifically debugging

## Problem-Specific Optimizations

### For This NC 31 Viewer Issue:
1. **Primary Fix**: Intelligent fallback in `registerScripts()`
2. **Secondary Fix**: Exponential backoff in JS
3. **Safety Net**: Try-catch with fallback everywhere
4. **Verification**: Check for double registration

### Quick Validation Commands
```bash
php -l lib/AppInfo/Application.php && \
grep -q "LoggerInterface" lib/AppInfo/Application.php && \
grep -q "exponential" js/register-viewer.js && \
echo "✅ Ready" || echo "❌ Check files"
```

## Error Recovery Patterns

### If Human Reports Error:
1. Ask for exact error message
2. Provide targeted fix (not complete rewrite)
3. Add more try-catch/fallbacks
4. Suggest simpler alternative if complex approach fails

### Common Fixes:
- **Syntax Error**: Run `php -l <file>`
- **Class Not Found**: Check namespace/use statements
- **JS Not Loading**: Check script registration
- **Double Registration**: Search for duplicate `Util::addScript`

## Efficiency Techniques

### Code Block Format:
```language
// filepath: /exact/path/to/file.ext
// ...existing code...
NEW OR MODIFIED CODE HERE
// ...existing code...
```

### Testing Format:
```bash
command && echo "✅" || echo "❌"
```

### Decision Tree:
1. Is LoadViewer event available? → Use it with fallback
2. Is Viewer app installed? → Register immediately
3. Multiple attempts needed? → Exponential backoff
4. Still failing? → Log and gracefully degrade

## Success Metrics
- ✅ RAW files open in Viewer
- ✅ No new bugs
- ✅ Verification command passes
- ✅ < 1 min manual validation
- ✅ Fallbacks cover failures

## Final Checklist
- [ ] Syntax OK (php -l)
- [ ] LoggerInterface present
- [ ] No duplicate Util::addScript
- [ ] JS backoff present
- [ ] Test command documented