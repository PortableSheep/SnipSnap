# PII Redaction Feature

SnipSnap automatically detects and suggests redactions for sensitive information in screenshots using OCR.

## How It Works

1. **Automatic Detection**: When OCR indexing is enabled, screenshots are scanned for text
2. **Pattern Matching**: Text is analyzed against regex patterns for common PII types
3. **Visual Indicators**: Detected areas are highlighted with dashed orange borders in the editor
4. **User Control**: You can accept, dismiss individual suggestions, or batch process all

## Detected PII Types

### Contact Information
- **Email addresses** - john@example.com, user+tag@company.co.uk
- **Phone numbers** - (555) 123-4567, +1-555-123-4567, 555.123.4567

### Financial Data
- **Credit cards** - 4532-1488-0343-6467 (validated with Luhn algorithm)
- **Account numbers** - 8-17 digit sequences

### Government IDs
- **Social Security Numbers** - 123-45-6789, 123 45 6789

### Technical Secrets
- **API keys/tokens** - Long alphanumeric strings (24+ chars)
- **AWS Access Keys** - AKIA followed by 16 characters
- **Private keys** - PEM format headers (-----BEGIN PRIVATE KEY-----)
- **URLs with tokens** - https://api.com?token=secret

### Personal Information
- **Street addresses** - 123 Main Street, 4567 Oak Ave
- **Dates of birth** - 03/15/1985, 12-25-1990
- **IP addresses** - 192.168.1.1, 10.0.0.255

## Using the Feature

### In the Editor

When sensitive information is detected, you'll see:

1. **Banner at the top** showing count and types of detected items
2. **Dashed orange outlines** around sensitive areas on the canvas
3. **Semi-transparent orange fill** for visibility

### Actions Available

- **Accept** - Adds a pixelate blur annotation to hide the sensitive text
- **Dismiss** - Removes the suggestion without adding blur
- **Accept All** - Applies blur to all detected items at once
- **Dismiss All** - Clears all suggestions

### Removing False Positives

If the detector flags something incorrectly:

1. Click **Dismiss** on individual suggestions
2. Or use **Dismiss All** and manually add blur where needed
3. Blur annotations can be deleted like any other annotation

## Privacy

- All detection runs **locally** using macOS Vision framework
- No data is sent to external servers
- OCR text is stored in local metadata files
- Detection is **opt-in** via Preferences → Enable Smart Redaction

## Pattern Details

### Credit Card Validation

Credit card numbers are validated using the Luhn algorithm to reduce false positives. This means:
- ✅ Valid: 4532-1488-0343-6467 (passes checksum)
- ❌ Invalid: 1234-5678-9012-3456 (fails checksum, not flagged)

### Token Detection

Long alphanumeric strings are flagged as potential tokens/keys:
- Minimum length: 24 characters
- Allowed chars: A-Z, a-z, 0-9, underscore, dash
- Catches: API keys, session tokens, JWTs

### Address Detection

Street addresses must include:
- House number (1-5 digits)
- Street name (capitalized words)
- Street type suffix (Street, St, Avenue, Ave, etc.)

## Limitations

- **Block-level precision**: Bounding boxes cover entire OCR text blocks, not individual words
- **OCR accuracy**: Detection depends on Vision framework's OCR quality
- **Pattern-based**: Uses regex patterns, not AI/ML classification
- **English-centric**: Patterns optimized for US/English text formats

## Configuration

Enable/disable in **Preferences → General**:
- ☑️ Enable OCR Indexing (required for detection)
- ☑️ Enable Smart Redaction Detection

## Technical Details

### Architecture

```
Screenshot → OCR (Vision) → RedactionDetector → Suggestions → Editor UI
```

1. **OCR phase**: Vision framework extracts text and bounding boxes
2. **Detection phase**: Regex patterns scan extracted text
3. **Storage**: Candidates saved in capture metadata JSON
4. **Display**: Editor loads suggestions and draws indicators

### Adding New Patterns

To add detection for new PII types:

1. Add case to `RedactionKind` enum in `CaptureMetadata.swift`
2. Add pattern to `RedactionDetector.Patterns`
3. Add detection loop in `RedactionDetector.detect()`
4. Update `RedactionSuggestion.kindLabel` and `.icon`
5. Rebuild and test

## Future Improvements

- [ ] Word-level bounding boxes (requires character-level OCR)
- [ ] Passport numbers
- [ ] Driver's license numbers
- [ ] More international phone formats
- [ ] IBAN/routing numbers
- [ ] Medical record numbers
- [ ] Custom user-defined patterns
