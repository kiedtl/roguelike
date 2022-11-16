from PIL import Image

im = Image.open("data/font/spleen.png")

oldbytes = im.tobytes()
newbytes = []
for i in range(len(oldbytes)):
    col = i % (8 * 16)
    if col == 0:
        newbytes += [0,0,0,0]
        newbytes.append(oldbytes[i])
    elif col == 127:
        newbytes.append(oldbytes[i])
        newbytes += [0,0,0,0]
    elif col % 8 == 0:
        newbytes += [0,0,0,0,0,0,0,0]
        newbytes.append(oldbytes[i])
    else:
        newbytes.append(oldbytes[i])

print(len(newbytes))
newim = Image.frombytes('L', (256, 10464), bytes(newbytes))
newim.save("out.png")
