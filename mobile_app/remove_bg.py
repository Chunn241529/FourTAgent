from PIL import Image

def remove_black_background(input_path, output_path):
    img = Image.open(input_path).convert("RGBA")
    datas = img.getdata()

    newData = []
    # Bản gốc này thuần đen rất dễ xử lí
    for item in datas:
        # Nếu màu R, G, B dưới 10 thì xem như nền đen (rất đen)
        if item[0] < 15 and item[1] < 15 and item[2] < 15:
            # Thành trong suốt
            newData.append((0, 0, 0, 0))
        else:
            newData.append(item)

    img.putdata(newData)
    img.save(output_path, "PNG")

remove_black_background("/home/trung/.gemini/antigravity/brain/6f7c4122-ae1e-4564-90a3-f3d93cfbc285/black_hole_logo_no_text_1771723753427.png", "/home/trung/.gemini/antigravity/brain/6f7c4122-ae1e-4564-90a3-f3d93cfbc285/black_hole_logo_no_text_transparent_clean.png")
