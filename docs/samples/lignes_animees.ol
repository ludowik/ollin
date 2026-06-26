var W = window.width
var H = window.height
const N = 150
const SPEED = 3

var x1=[] var y1=[] var x2=[] var y2=[]
var vx1=[] var vy1=[] var vx2=[] var vy2=[]
var cols=[]
for i = 1, N do
    x1[i]=math.rand_int(0,W)  y1[i]=math.rand_int(0,H)
    x2[i]=math.rand_int(0,W)  y2[i]=math.rand_int(0,H)
    vx1[i]=math.rand(-SPEED,SPEED)  vy1[i]=math.rand(-SPEED,SPEED)
    vx2[i]=math.rand(-SPEED,SPEED)  vy2[i]=math.rand(-SPEED,SPEED)
    cols[i]=Color.random()
end

graphics.canvas(W, H, "Lignes")

func frame()
    graphics.clear(colors.BLACK)
    graphics.strokeSize(1)
    for i = 1, N do
        x1[i]+=vx1[i]  y1[i]+=vy1[i]  x2[i]+=vx2[i]  y2[i]+=vy2[i]
        if x1[i]<0 or x1[i]>W then vx1[i]=-vx1[i] end
        if y1[i]<0 or y1[i]>H then vy1[i]=-vy1[i] end
        if x2[i]<0 or x2[i]>W then vx2[i]=-vx2[i] end
        if y2[i]<0 or y2[i]>H then vy2[i]=-vy2[i] end
        graphics.stroke(cols[i])
        graphics.line(x1[i],y1[i],x2[i],y2[i])
    end
    graphics.draw_text("FPS: "+graphics.fps(), W-80, H-20, 16)
end

graphics.run(frame)
