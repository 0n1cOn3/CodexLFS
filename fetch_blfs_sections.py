#!/usr/bin/env python3
"""Fetch BLFS instructions for development purposes."""
import sys
import requests
from bs4 import BeautifulSoup

BASE_URL = "https://www.linuxfromscratch.org/blfs/view/stable"


def fetch_package(url: str):
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    soup = BeautifulSoup(r.text, "html.parser")
    title = soup.find("h1").get_text(strip=True)
    print(f"# {title}\n")
    for pre in soup.select("pre.userinput"):
        print(pre.get_text().strip())
        print()


def fetch_chapter(ch: str):
    index_url = f"{BASE_URL}/{ch}/"
    r = requests.get(index_url, timeout=30)
    r.raise_for_status()
    soup = BeautifulSoup(r.text, "html.parser")
    for a in soup.select('a[href$=".html"]'):
        href = a.get("href")
        if href == "index.html":
            continue
        fetch_package(f"{BASE_URL}/{ch}/{href}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: fetch_blfs_sections.py CHAPTER [CHAPTER ...]")
        sys.exit(1)
    for chapter in sys.argv[1:]:
        fetch_chapter(chapter)
