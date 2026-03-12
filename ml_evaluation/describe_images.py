"""
Vision Model Image Describer - Accessibility Focus
Describes images for blind/visually impaired users using local Ollama vision models.

Usage:
    python describe_images.py                        # describes all images in current folder
    python describe_images.py --folder ./my_images  # specify a folder
    python describe_images.py --image photo.jpg     # single image
    python describe_images.py --model llava          # use a different model
"""

import argparse
import base64
import json
import os
import sys
from pathlib import Path

import requests

# --- Config ---
OLLAMA_URL = "http://localhost:11434/api/generate"
DEFAULT_MODEL = "llama3.2-vision"
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}

SYSTEM_PROMPT = """You are an accessibility assistant helping blind and visually impaired people 
understand images. Your descriptions should be detailed, practical, and prioritize information 
that matters most for navigation, safety, and context.

Always describe in this order of priority:
1. TEXT and SIGNS - Read all visible text, signs, labels, warnings, prices, menus, street signs exactly
2. PEOPLE - Number of people, approximate age/gender if relevant, what they're doing, facial expressions
3. SAFETY-RELEVANT elements - obstacles, hazards, steps, traffic, exits
4. LOCATION CONTEXT - What kind of place is this? Indoor/outdoor? Public/private?
5. KEY OBJECTS - Important objects and their positions (left, right, center, foreground, background)
6. COLORS and LIGHTING - Only when relevant to understanding the scene
7. OVERALL SCENE - Brief summary of what's happening

Be specific about positions (e.g., "a red stop sign in the upper right", "stairs directly ahead").
Avoid vague terms like "some things" or "various items" - be precise.
Keep descriptions focused and useful, not poetic."""


def load_image_as_base64(image_path: str) -> str:
    """Load an image file and encode it as base64."""
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def describe_image(image_path: str, model: str = DEFAULT_MODEL) -> str:
    """Send an image to Ollama and get an accessibility-focused description."""
    print(f"  Analyzing: {Path(image_path).name} ...", end="", flush=True)

    image_b64 = load_image_as_base64(image_path)

    payload = {
        "model": model,
        "prompt": (
            "Please describe this image for a blind person. "
            "Prioritize any text, signs, safety hazards, and important spatial information. "
            "Be specific and practical."
        ),
        "system": SYSTEM_PROMPT,
        "images": [image_b64],
        "stream": False,
    }

    try:
        response = requests.post(OLLAMA_URL, json=payload, timeout=120)
        response.raise_for_status()
        result = response.json()
        print(" done.")
        return result.get("response", "No response received.")
    except requests.exceptions.ConnectionError:
        print(" ERROR.")
        return "ERROR: Could not connect to Ollama. Is it running? Try: ollama serve"
    except requests.exceptions.Timeout:
        print(" TIMEOUT.")
        return "ERROR: Request timed out. The model may still be loading."
    except Exception as e:
        print(" ERROR.")
        return f"ERROR: {str(e)}"


def find_images(folder: str) -> list[Path]:
    """Find all image files in a folder."""
    folder_path = Path(folder)
    if not folder_path.exists():
        print(f"Error: Folder '{folder}' does not exist.")
        sys.exit(1)

    images = [
        p for p in sorted(folder_path.iterdir())
        if p.suffix.lower() in IMAGE_EXTENSIONS
    ]
    return images


def check_ollama_running() -> bool:
    """Check if Ollama is running and accessible."""
    try:
        response = requests.get("http://localhost:11434/api/tags", timeout=5)
        return response.status_code == 200
    except Exception:
        return False


def check_model_available(model: str) -> bool:
    """Check if the specified model is pulled and available."""
    try:
        response = requests.get("http://localhost:11434/api/tags", timeout=5)
        models = response.json().get("models", [])
        model_names = [m["name"].split(":")[0] for m in models]
        return model.split(":")[0] in model_names
    except Exception:
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Describe images for blind/visually impaired users using Ollama vision models."
    )
    parser.add_argument("--folder", "-f", default=".", help="Folder containing images (default: current folder)")
    parser.add_argument("--image", "-i", help="Describe a single image file")
    parser.add_argument("--model", "-m", default=DEFAULT_MODEL, help=f"Ollama model to use (default: {DEFAULT_MODEL})")
    parser.add_argument("--output", "-o", help="Save results to a text file")
    args = parser.parse_args()

    # --- Preflight checks ---
    print(f"\n🔍 Vision Accessibility Describer")
    print(f"   Model: {args.model}")
    print()

    if not check_ollama_running():
        print("❌ Ollama is not running. Start it with:\n   ollama serve\n")
        sys.exit(1)

    if not check_model_available(args.model):
        print(f"❌ Model '{args.model}' is not pulled. Get it with:")
        print(f"   ollama pull {args.model}\n")
        print("Other good vision models to try:")
        print("   ollama pull llava")
        print("   ollama pull moondream")
        sys.exit(1)

    print(f"✅ Ollama running | Model '{args.model}' ready\n")
    print("-" * 60)

    # --- Collect images to process ---
    if args.image:
        image_path = Path(args.image)
        if not image_path.exists():
            print(f"Error: Image '{args.image}' not found.")
            sys.exit(1)
        images = [image_path]
    else:
        images = find_images(args.folder)
        if not images:
            print(f"No images found in '{args.folder}'")
            print(f"Supported formats: {', '.join(IMAGE_EXTENSIONS)}")
            sys.exit(0)
        print(f"Found {len(images)} image(s) in '{args.folder}'\n")

    # --- Process images ---
    results = []

    for i, image_path in enumerate(images, 1):
        print(f"[{i}/{len(images)}]")
        description = describe_image(str(image_path), model=args.model)

        results.append({
            "file": image_path.name,
            "description": description
        })

        print(f"\n📷 {image_path.name}")
        print(f"{description}\n")
        print("-" * 60)

    # --- Save output if requested ---
    if args.output:
        output_path = Path(args.output)
        with open(output_path, "w") as f:
            f.write(f"Image Accessibility Descriptions\n")
            f.write(f"Model: {args.model}\n")
            f.write("=" * 60 + "\n\n")
            for r in results:
                f.write(f"FILE: {r['file']}\n")
                f.write("-" * 40 + "\n")
                f.write(r["description"] + "\n\n")
        print(f"\n💾 Results saved to: {output_path}")

    print(f"\n✅ Done! Processed {len(images)} image(s).")


if __name__ == "__main__":
    main()