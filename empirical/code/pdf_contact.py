"""Compose rendered PDF pages into contact sheets for visual layout QA."""
from pathlib import Path
from PIL import Image, ImageDraw

pages = sorted((Path(__file__).resolve().parents[1] / "validation" / "pdf_pages").glob("page-*.png"))
out = Path(__file__).resolve().parents[1] / "validation"
for chunk in range(0, len(pages), 6):
    selection = pages[chunk:chunk+6]
    thumbs = []
    for file in selection:
        im = Image.open(file).convert("RGB")
        im.thumbnail((450, 650))
        thumbs.append(im)
    board = Image.new("RGB", (3*470, 2*700), "#e6e9eb")
    d = ImageDraw.Draw(board)
    for j, (file, im) in enumerate(zip(selection, thumbs)):
        x = (j%3)*470+10
        y = (j//3)*700+28
        board.paste(im, (x,y))
        d.text((x,y-20), file.stem, fill="black")
    board.save(out / f"pdf_contact_{chunk//6+1}.png")
