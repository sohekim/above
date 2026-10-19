import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let out=root.appendingPathComponent("outputs/LookUp-launch-assets")
let skies=["blue","gray","pink"].map { NSImage(contentsOf:root.appendingPathComponent("outputs/Above/Above/DemoSkies/\($0).png"))! }
func canvas(_ w:Int,_ h:Int,_ draw:(CGFloat,CGFloat)->Void)->NSImage {
 let image=NSImage(size:NSSize(width:w,height:h));image.lockFocus()
 NSColor(calibratedWhite:0.98,alpha:1).setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:w,height:h)).fill()
 draw(CGFloat(w),CGFloat(h));image.unlockFocus();return image
}

func save(_ img:NSImage,_ name:String) {
 let rep=NSBitmapImageRep(data:img.tiffRepresentation!)!
 try! rep.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name))
}
func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ size:CGFloat,_ weight:NSFont.Weight = .regular,_ color:NSColor = .black) {
 let para=NSMutableParagraphStyle();para.lineSpacing = -size*0.04
 (s as NSString).draw(in:NSRect(x:x,y:y,width:w,height:size*4),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.kern:-size*0.035,.paragraphStyle:para])
}
func circle(_ image:NSImage,_ x:CGFloat,_ y:CGFloat,_ side:CGFloat){
 NSGraphicsContext.saveGraphicsState();NSBezierPath(ovalIn:NSRect(x:x,y:y,width:side,height:side)).addClip()
 let source=image.size;let crop=min(source.width,source.height)
 image.draw(in:NSRect(x:x,y:y,width:side,height:side),from:NSRect(x:(source.width-crop)/2,y:(source.height-crop)/2,width:crop,height:crop),operation:.sourceOver,fraction:1)
 NSGraphicsContext.restoreGraphicsState()
}
let icon=canvas(1024,1024){_,_ in circle(skies[0],132,132,760) }
save(icon,"LookUp-icon-1024.png")
let titles=["A little sky.\nEvery day.","Ten seconds.\nJust look up.","Keep a moment.\nLeave a thought."]
var posters:[NSImage]=[]
for i in 0..<3 {
 let img=canvas(1320,2868){w,h in
  text("LookUp",90,h-220,600,42,.semibold)
  text(String(format:"0%d /",i+1),1100,h-205,160,28,.medium)
  text(titles[i],90,h-700,w-180,108,.bold)
  if i==0 {
   text("Your skies, collected.",90,h-850,w-180,38)
   let originY:CGFloat=360,side:CGFloat=145,gap:CGFloat=20
   for row in 0..<6 {for col in 0..<7 {
    let idx=row*7+col;let x=90+CGFloat(col)*(side+gap),y=originY+CGFloat(5-row)*(side+gap)
    if idx%4==0 || idx%7==2 {circle(skies[idx%3],x,y,side)} else {
      NSColor(calibratedWhite:0.94,alpha:1).setFill();NSBezierPath(ovalIn:NSRect(x:x,y:y,width:side,height:side)).fill()
    }
   }}
  } else if i==1 {
   circle(skies[0],160,620,1000)
   let path=NSBezierPath();path.appendArc(withCenter:NSPoint(x:660,y:1120),radius:520,startAngle:90,endAngle:340,clockwise:true)
   path.lineWidth=5;NSColor.black.setStroke();path.stroke()
   text("A quiet pause in your day.",90,320,w-180,38)
  } else {
   circle(skies[2],210,1050,900)
   text("october 19",90,780,w-180,72,.bold)
   text("leave a little thought…",90,520,w-180,48,.regular,.gray)
  }
  NSColor.black.setFill();NSBezierPath(rect:NSRect(x:90,y:190,width:w-180,height:2)).fill()
  text("A SKY DIARY",90,82,700,26,.semibold)
 }
 posters.append(img);save(img,"0\(i+1)-poster-draft.png")
}
let sheet=canvas(1200,950){_,_ in
 for (i,img) in posters.enumerated(){img.draw(in:NSRect(x:CGFloat(i)*400+12,y:60,width:376,height:817))}
 text("LookUp / promotional concepts — actual app screenshots to be inserted before submission",24,10,1150,18,.medium)
}
save(sheet,"overview.png")
