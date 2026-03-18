#!/usr/bin/env python3
"""Generate or update a Sparkle appcast.xml file for SnipSnap releases."""

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime
from xml.dom.minidom import parseString

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"

CHANNEL_TITLE = "SnipSnap Updates"
CHANNEL_LINK = "https://portablesheep.github.io/SnipSnap/appcast.xml"
CHANNEL_DESC = "SnipSnap update feed"


def parse_signature(sig_string):
    """Parse Sparkle sign_update output into (signature, length) tuple.

    Expected format: sparkle:edSignature="BASE64" length="12345"
    Returns (signature, length) or (None, None) on failure.
    """
    sig_match = re.search(r'sparkle:edSignature="([^"]+)"', sig_string)
    len_match = re.search(r'length="(\d+)"', sig_string)
    signature = sig_match.group(1) if sig_match else None
    length = len_match.group(1) if len_match else None
    return signature, length


def markdown_to_html(md_text):
    """Convert simple markdown to basic HTML for Sparkle release notes."""
    lines = md_text.strip().splitlines()
    html_lines = []
    in_list = False

    for line in lines:
        stripped = line.strip()

        if not stripped:
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            html_lines.append("")
            continue

        # Headers
        header_match = re.match(r"^(#{1,6})\s+(.+)$", stripped)
        if header_match:
            if in_list:
                html_lines.append("</ul>")
                in_list = False
            level = len(header_match.group(1))
            text = _inline_formatting(header_match.group(2))
            html_lines.append(f"<h{level}>{text}</h{level}>")
            continue

        # List items
        list_match = re.match(r"^[-*]\s+(.+)$", stripped)
        if list_match:
            if not in_list:
                html_lines.append("<ul>")
                in_list = True
            text = _inline_formatting(list_match.group(1))
            html_lines.append(f"<li>{text}</li>")
            continue

        # Plain paragraph
        if in_list:
            html_lines.append("</ul>")
            in_list = False
        text = _inline_formatting(stripped)
        html_lines.append(f"<p>{text}</p>")

    if in_list:
        html_lines.append("</ul>")

    return "\n".join(html_lines)


def _inline_formatting(text):
    """Convert inline markdown formatting to HTML."""
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"__(.+?)__", r"<strong>\1</strong>", text)
    text = re.sub(r"\*(.+?)\*", r"<em>\1</em>", text)
    text = re.sub(r"_(.+?)_", r"<em>\1</em>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return text


def build_item_element(version, build, url, signature, length, changelog, min_os):
    """Build an <item> Element for a single release.

    Returns (item_element, cdata_html) where cdata_html is the raw HTML
    that should be placed inside a CDATA section in the final output.
    A unique placeholder is stored in the description element text.
    """
    item = ET.Element("item")

    title = ET.SubElement(item, "title")
    title.text = f"Version {version}"

    sv = ET.SubElement(item, f"{{{SPARKLE_NS}}}version")
    sv.text = build

    svs = ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString")
    svs.text = version

    msv = ET.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion")
    msv.text = min_os

    if changelog:
        html = f"\n        <h2>What's New in {version}</h2>\n        {markdown_to_html(changelog)}\n      "
    else:
        html = f"\n        <h2>What's New in {version}</h2>\n      "

    # Use a placeholder that will be swapped for CDATA post-serialization
    placeholder = f"__CDATA_{id(item)}__"
    desc = ET.SubElement(item, "description")
    desc.text = placeholder

    pub = ET.SubElement(item, "pubDate")
    pub.text = format_datetime(datetime.now(timezone.utc), usegmt=True)

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", url)
    if signature:
        enclosure.set(f"{{{SPARKLE_NS}}}edSignature", signature)
    if length:
        enclosure.set("length", length)
    enclosure.set("type", "application/octet-stream")

    return item, (placeholder, html)


def load_existing_items(path):
    """Load existing <item> elements from an appcast file.

    Returns (items, cdata_map) where items is a list of Element objects
    and cdata_map is a dict of placeholder -> raw_html for CDATA content.
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        return [], {}

    # Extract CDATA content before stripping wrappers
    cdata_blocks = re.findall(
        r"<description><!\[CDATA\[(.*?)\]\]></description>",
        content,
        flags=re.DOTALL,
    )

    # Strip CDATA wrappers so ElementTree can parse the content
    content = re.sub(
        r"<!\[CDATA\[(.*?)\]\]>",
        lambda m: m.group(1),
        content,
        flags=re.DOTALL,
    )

    try:
        tree = ET.ElementTree(ET.fromstring(content))
    except ET.ParseError as exc:
        print(f"Warning: existing appcast is malformed ({exc}), overwriting.", file=sys.stderr)
        return [], {}

    items = []
    cdata_map = {}
    cdata_idx = 0
    for item in tree.iter("item"):
        desc = item.find("description")
        if desc is not None and cdata_idx < len(cdata_blocks):
            placeholder = f"__CDATA_{id(item)}__"
            raw_html = cdata_blocks[cdata_idx]
            # Clear any parsed child elements and set placeholder text
            for child in list(desc):
                desc.remove(child)
            desc.text = placeholder
            desc.tail = desc.tail  # preserve tail text
            cdata_map[placeholder] = raw_html
            cdata_idx += 1
        items.append(item)
    return items, cdata_map


def build_appcast(items):
    """Build a complete appcast RSS ElementTree from a list of <item> elements."""
    rss = ET.Element("rss")
    rss.set("version", "2.0")
    rss.set(f"xmlns:sparkle", SPARKLE_NS)
    rss.set(f"xmlns:dc", DC_NS)

    channel = ET.SubElement(rss, "channel")

    title = ET.SubElement(channel, "title")
    title.text = CHANNEL_TITLE

    link = ET.SubElement(channel, "link")
    link.text = CHANNEL_LINK

    desc = ET.SubElement(channel, "description")
    desc.text = CHANNEL_DESC

    lang = ET.SubElement(channel, "language")
    lang.text = "en"

    for item in items:
        channel.append(item)

    return ET.ElementTree(rss)


def prettify_xml(tree, cdata_map):
    """Serialize an ElementTree to a pretty-printed XML string with CDATA support."""
    ET.register_namespace("sparkle", SPARKLE_NS)
    ET.register_namespace("dc", DC_NS)

    raw = ET.tostring(tree.getroot(), encoding="unicode", xml_declaration=False)

    # ElementTree may duplicate namespace declarations; clean up and set them
    # explicitly on the <rss> element.
    raw = re.sub(r'\s*xmlns:sparkle="[^"]*"', "", raw)
    raw = re.sub(r'\s*xmlns:dc="[^"]*"', "", raw)
    raw = raw.replace(
        '<rss version="2.0"',
        f'<rss version="2.0" xmlns:sparkle="{SPARKLE_NS}" xmlns:dc="{DC_NS}"',
        1,
    )

    # Pretty print via minidom
    dom = parseString(raw)
    pretty = dom.toprettyxml(indent="  ", encoding=None)

    # Remove the xml declaration minidom adds (we'll add our own)
    lines = pretty.splitlines()
    if lines and lines[0].startswith("<?xml"):
        lines = lines[1:]
    # Remove blank lines minidom sometimes inserts
    cleaned = "\n".join(line for line in lines if line.strip())

    # Replace placeholders with CDATA-wrapped raw HTML
    for placeholder, html in cdata_map.items():
        escaped_placeholder = placeholder.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        # minidom may have escaped the placeholder text
        for variant in [placeholder, escaped_placeholder]:
            pattern = f"<description>{variant}</description>"
            replacement = f"<description><![CDATA[{html}]]></description>"
            if pattern in cleaned:
                cleaned = cleaned.replace(pattern, replacement, 1)
                break

    return f'<?xml version="1.0" encoding="utf-8"?>\n{cleaned}\n'


def main():
    parser = argparse.ArgumentParser(
        description="Generate or update a Sparkle appcast.xml for SnipSnap.",
    )
    parser.add_argument("--version", required=True, help="App version string (e.g. 1.0.0)")
    parser.add_argument("--build", required=True, help="Build number (e.g. 42)")
    parser.add_argument("--url", required=True, help="Download URL for the ZIP archive")
    parser.add_argument(
        "--signature",
        default="",
        help='Full EdDSA signature from sign_update (e.g. sparkle:edSignature="..." length="...")',
    )
    parser.add_argument("--size", default=None, help="File size in bytes (fallback if not in signature)")
    parser.add_argument("--changelog", default="", help="Release notes in markdown")
    parser.add_argument("--output", default="docs/appcast.xml", help="Output path (default: docs/appcast.xml)")
    parser.add_argument("--min-os", default="13.0", help="Minimum macOS version (default: 13.0)")
    args = parser.parse_args()

    # Parse signature string
    ed_signature, sig_length = parse_signature(args.signature)
    length = sig_length or args.size

    # Load existing items
    existing_items, cdata_map = load_existing_items(args.output)

    # Build the new item
    new_item, new_cdata = build_item_element(
        version=args.version,
        build=args.build,
        url=args.url,
        signature=ed_signature,
        length=length,
        changelog=args.changelog,
        min_os=args.min_os,
    )
    cdata_map[new_cdata[0]] = new_cdata[1]

    # Prepend new item
    all_items = [new_item] + existing_items

    # Build and write appcast
    tree = build_appcast(all_items)
    output = prettify_xml(tree, cdata_map)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(output)

    print(f"Appcast written to {args.output} ({len(all_items)} release(s))")


if __name__ == "__main__":
    main()
