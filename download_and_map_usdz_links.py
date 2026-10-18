import os
import re
import urllib.request
import json

md_path = "/Users/david/Downloads/usdz-links.md"
dest_dir = "/Users/david/Develop/MyMuseum/MyMuseum/ARModels"
mapping_file = "/Users/david/Develop/MyMuseum/MyMuseum/ar_model_catalog_mapping.json"
os.makedirs(dest_dir, exist_ok=True)

with open(md_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

items = []
current_section = "General"

for line in lines:
    line_str = line.strip()
    if line_str.startswith("## "):
        current_section = line_str.replace("## ", "").strip()
        continue
    
    # Match pattern: - Title: [下载](URL)
    match = re.search(r'-\s*(.+?):\s*\[下载\]\((https?://[^\s\)]+?\.usdz)\)', line_str)
    if match:
        title = match.group(1).strip()
        url = match.group(2).strip()
        filename = os.path.basename(url)
        items.append({
            "section": current_section,
            "title": title,
            "url": url,
            "filename": filename
        })

print(f"Parsed {len(items)} items from {md_path}:")
headers = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"}

downloaded = 0
for item in items:
    dest_path = os.path.join(dest_dir, item["filename"])
    if not os.path.exists(dest_path) or os.path.getsize(dest_path) < 1000:
        print(f"Downloading [{item['title']}] -> {item['filename']}...")
        try:
            req = urllib.request.Request(item["url"], headers=headers)
            with urllib.request.urlopen(req, timeout=30) as resp, open(dest_path, "wb") as out:
                out.write(resp.read())
            mb = os.path.getsize(dest_path) / (1024 * 1024)
            print(f"  OK ({mb:.2f} MB)")
            downloaded += 1
        except Exception as e:
            print(f"  Error downloading {item['filename']}: {e}")
    else:
        mb = os.path.getsize(dest_path) / (1024 * 1024)
        print(f"Already exists: {item['filename']} ({mb:.2f} MB)")

print(f"Download complete. {downloaded} newly downloaded.")

