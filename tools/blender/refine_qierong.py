"""Qierong reference-matching revision. Original geometry and procedural PBR textures.
Run build() in Blender. Creates its own scene; existing scenes remain intact.
"""
import bpy, math, json, random
from mathutils import Vector
from pathlib import Path
from math import pi,sin,cos,sqrt
import numpy as np
BASE=Path(r"D:\Projects\Codex\xiuxian")
WORK=BASE/"work"/"qierong-refinement"
OUT=BASE/"assets"/"blender"
TEX=OUT/"textures"
RENDER=BASE/"docs"/"screenshots"/"qierong-v2"
for p in (WORK,TEX,RENDER):p.mkdir(parents=True,exist_ok=True)
random.seed(319)
V=[];F=[];UV=[];FM=[];VG=[];M=[];MI={};scene=None;rig=None
PALETTE={
"bark":("4a3523",.80,0),"grain":("6c5235",.78,0),"groove":("2a261b",.88,0),
"jade":("315b49",.57,0),"leaf":("43735c",.62,0),"leaflight":("578064",.60,0),
"leafdark":("25483d",.69,0),"vein":("9b9453",.62,.15),
"ivory":("e5d9b6",.48,0),"gold":("b69350",.42,.65),
"hoof":("302b22",.73,0),"eye":("102b26",.24,0),"iris":("378c76",.31,0),
"glow":("80eadb",.22,0),"white":("fff0ce",.27,0),"moss":("78864b",.91,0)}
def linear(h):
    return tuple((c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4) for c in (int(h[i:i+2],16)/255 for i in (0,2,4)))
def make_materials():
    for name,(h,r,m) in PALETTE.items():
        mat=bpy.data.materials.new("Q2_"+name);mat.use_nodes=True
        node=next(n for n in mat.node_tree.nodes if n.type=="BSDF_PRINCIPLED")
        node.inputs["Base Color"].default_value=(*linear(h),1)
        node.inputs["Roughness"].default_value=r;node.inputs["Metallic"].default_value=m
        mat.diffuse_color=(*linear(h),1)
        if name=="glow":
            node.inputs["Emission Color"].default_value=(*linear(h),1)
            node.inputs["Emission Strength"].default_value=1.3
        MI[name]=len(M);M.append(mat)
    # Original tileable wood albedo and tangent-space normal, both exported to glTF.
    n=1024
    yy,xx=np.mgrid[0:n,0:n].astype(np.float32)/n
    warp=xx+.045*np.sin(yy*2*pi*3+np.sin(xx*2*pi)*2)+.018*np.sin(yy*2*pi*9+xx*2*pi)
    bands=np.sin(warp*2*pi*36+np.sin(yy*2*pi*4)*1.1)
    fine=np.sin(warp*2*pi*121+yy*2*pi*5)
    height=.45+.15*bands+.035*fine
    cracks=np.maximum(0,np.sin(warp*2*pi*36+np.sin(yy*2*pi*4)*1.1))**16
    color=(.86+.08*bands+.03*fine-.15*cracks)
    rgba=np.ones((n,n,4),np.float32)
    for i,c in enumerate((.31,.235,.155)):rgba[:,:,i]=c*color
    base=bpy.data.images.new("Qierong bark basecolor",width=n,height=n)
    base.pixels.foreach_set(rgba.ravel());base.filepath_raw=str(TEX/"qierong_bark_basecolor.png")
    base.file_format="PNG";base.save();base.pack()
    dy,dx=np.gradient(height)
    nx=-dx*34;ny=-dy*34;nz=np.ones_like(nx)
    norm=np.sqrt(nx*nx+ny*ny+nz*nz)
    for i,c in enumerate((nx,ny,nz)):rgba[:,:,i]=c/norm*.5+.5
    normal=bpy.data.images.new("Qierong bark normal",width=n,height=n)
    normal.colorspace_settings.name="Non-Color"
    normal.pixels.foreach_set(rgba.ravel());normal.filepath_raw=str(TEX/"qierong_bark_normal.png")
    normal.file_format="PNG";normal.save();normal.pack()
    mat=M[MI["bark"]];nodes=mat.node_tree.nodes;links=mat.node_tree.links
    shader=next(n for n in nodes if n.type=="BSDF_PRINCIPLED")
    tex=nodes.new("ShaderNodeTexImage");tex.image=base;tex.label="Exported wood basecolor"
    links.new(tex.outputs["Color"],shader.inputs["Base Color"])
    texn=nodes.new("ShaderNodeTexImage");texn.image=normal;texn.label="Exported tangent normal"
    nmap=nodes.new("ShaderNodeNormalMap");nmap.inputs["Strength"].default_value=.28
    links.new(texn.outputs["Color"],nmap.inputs["Color"]);links.new(nmap.outputs["Normal"],shader.inputs["Normal"])
def patch(v,f,uv,mat,bone="body"):
    off=len(V);V.extend(tuple(p) for p in v);UV.extend(uv);VG.extend([bone]*len(v))
    F.extend(tuple(off+i for i in face) for face in f);FM.extend([MI[mat]]*len(f))
def catmull(points,steps=6):
    p=[Vector(x) for x in points];out=[]
    for i in range(len(p)-1):
        a=p[max(0,i-1)];b=p[i];c=p[i+1];d=p[min(len(p)-1,i+2)]
        for j in range(steps):
            t=j/steps
            out.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t**3))
    return out+[p[-1]]
def tube(points,radii,mat,bone="body",sides=8,steps=4,flute=0):
    ps=catmull(points,steps);verts=[];faces=[];uv=[];length=0
    for i,p in enumerate(ps):
        t=i/(len(ps)-1)*(len(radii)-1);k=min(int(t),len(radii)-2)
        r=radii[k]*(1-(t-k))+radii[k+1]*(t-k)
        direction=ps[min(i+1,len(ps)-1)]-ps[max(0,i-1)]
        direction.normalize();u=direction.cross(Vector((0,1,0)))
        if u.length<.01:u=direction.cross(Vector((1,0,0)))
        u.normalize();v=direction.cross(u).normalized()
        if i:length+=(p-ps[i-1]).length
        for j in range(sides+1):
            a=j*2*pi/sides;rr=r*(1+flute*cos(a*5+i*.15))
            verts.append(p+rr*(cos(a)*u+sin(a)*v));uv.append((j/sides,length*.45))
    for i in range(len(ps)-1):
        for j in range(sides):
            a=i*(sides+1)+j;faces.append((a,a+1,a+sides+2,a+sides+1))
    faces.extend([tuple(reversed(range(sides))),tuple((len(ps)-1)*(sides+1)+j for j in range(sides))])
    patch(verts,faces,uv,mat,bone)
def ell(p,s,mat,bone="body",seg=24,rings=12):
    verts=[];uv=[];faces=[]
    for k in range(rings+1):
        a=pi*k/rings
        for j in range(seg+1):
            t=j*2*pi/seg
            verts.append((p[0]+s[0]*sin(a)*cos(t),p[1]+s[1]*sin(a)*sin(t),p[2]+s[2]*cos(a)))
            uv.append((j/seg,k/rings))
    for k in range(rings):
        for j in range(seg):
            a=k*(seg+1)+j;faces.append((a,a+seg+1,a+seg+2,a+1))
    patch(verts,faces,uv,mat,bone)
def leaf(a,b,w,mat="jade",bone="head",vein=True):
    a=Vector(a);b=Vector(b);d=b-a
    u=d.cross(Vector((0,1,0)))
    if u.length<.01:u=d.cross(Vector((1,0,0)))
    u.normalize();normal=u.cross(d).normalized()
    verts=[];uv=[];f=[];rows=6;cols=4
    for layer in (-1,1):
        for i in range(rows+1):
            t=i/rows;shape=max(.025,sin(pi*t)**.72)*(1-.28*t)
            for j in range(cols+1):
                s=-1+2*j/cols
                # Raised midrib, cupped edges and swept tip make a curved botanical blade.
                p=a+d*t+u*(s*w*shape)+normal*(-sin(pi*t)*w*(.28-.20*s*s)+layer*.006)
                p.y-=sin(pi*t)*.025
                verts.append(p);uv.append((j/cols,t))
    stride=(rows+1)*(cols+1)
    for layer in range(2):
        off=layer*stride
        for i in range(rows):
            for j in range(cols):
                q=off+i*(cols+1)+j
                f.append((q,q+cols+1,q+cols+2,q+1) if layer==0 else (q+1,q+cols+2,q+cols+1,q))
    for i in range(rows):
        for j in (0,cols):
            q=i*(cols+1)+j
            f.append((q,q+stride,q+stride+cols+1,q+cols+1))
    patch(verts,f,uv,mat,bone)
    if vein:
        pts=[a+d*t-normal*(sin(pi*t)*w*.28+.014) for t in (.05,.3,.6,.88)]
        tube(pts,[.007,.008,.006,.001],"vein",bone,5,2)
def ring(center,r,thick,mat,bone="body",axis="Z"):
    pts=[]
    for j in range(33):
        t=j*2*pi/32
        offset=(cos(t)*r,sin(t)*r,0) if axis=="Z" else (0,cos(t)*r,sin(t)*r)
        pts.append(Vector(center)+Vector(offset))
    tube(pts,[thick]*len(pts),mat,bone,6,1)
def face_loft():
    # A continuous tapered deer mask replaces the former sphere and toy muzzle.
    profiles=[(2.68,.095,.08,-1.17),(2.77,.19,.18,-1.18),(2.92,.235,.23,-1.10),
              (3.05,.29,.265,-.99),(3.25,.35,.25,-.91),(3.43,.26,.18,-.84),(3.50,.06,.05,-.82)]
    ps=catmull(profiles,4);v=[];uv=[];f=[];sides=32
    for i,(z,w,depth,y) in enumerate(ps):
        for j in range(sides+1):
            t=j*2*pi/sides
            v.append((cos(t)*w,y+sin(t)*depth,z));uv.append((j/sides,i/(len(ps)-1)))
    for i in range(len(ps)-1):
        for j in range(sides):
            a=i*(sides+1)+j;f.append((a,a+1,a+sides+2,a+sides+1))
    f.extend([tuple(reversed(range(sides))),tuple((len(ps)-1)*(sides+1)+j for j in range(sides))])
    patch(v,f,uv,"ivory","head")
def almond(side):
    def surface(x,z):
        return -.935-.255*sqrt(max(.045,1-(x/.345)**2))
    x=side*.22;z=3.18
    center=Vector((x,surface(x,z)-.009,z))
    outline=[]
    for i in range(25):
        a=i*2*pi/24;xx=x+cos(a)*.105;zz=z+sin(a)*.057+side*cos(a)*.028
        outline.append(Vector((xx,surface(xx,zz)-.014,zz)))
    v=[center+Vector((0,-.018,0))]+outline
    patch(v,[(0,i+1,(i+1)%24+1) for i in range(24)],[(0,0)]*len(v),"eye","head")
    tube(outline,[.012]*len(outline),"jade","head",6,1)
    ell(center+Vector((0,-.028,.003)),(.036,.012,.047),"iris","head",16,8)
    ell(center+Vector((0,-.040,.003)),(.012,.006,.032),"eye","head",12,8)
    ell(center+Vector((-.010,-.049,.021)),(.010,.005,.011),"white","head",10,6)
    pts=[]
    for xx,zz in ((side*.09,3.27),(side*.21,3.31),(side*.33,3.31)):
        pts.append((xx,surface(xx,zz)-.015,zz))
    tube(pts,[.023,.030,.003],"jade","head",8,5)
def hoof(x,y,bone):
    for toe in (-1,1):
        verts=[];uv=[];faces=[];sides=20
        for row,(z,w,d) in enumerate(((.025,.073,.18),(.13,.082,.19),(.27,.060,.13))):
            for j in range(sides):
                a=j*2*pi/sides
                xx=math.copysign(abs(cos(a))**.6,cos(a))*w
                yy=math.copysign(abs(sin(a))**.6,sin(a))*d
                verts.append((x+toe*.083+xx,y-.045+yy,z));uv.append((j/sides,row/2))
        for row in range(2):
            for j in range(sides):
                a=row*sides+j;b=row*sides+(j+1)%sides
                faces.append((a,b,b+sides,a+sides))
        faces.extend([tuple(reversed(range(sides))),tuple(2*sides+j for j in range(sides))])
        patch(verts,faces,uv,"hoof",bone)
def armor(side):
    first=len(V)
    # Solid shoulder shield with an inset jade disc and angular leiwen-style relief.
    center=(side*.64,-.49,1.91)
    ell(center,(.065,.31,.31),"gold","body",32,12)
    ell((side*.70,-.49,1.91),(.024,.262,.262),"jade","body",32,8)
    ring((side*.725,-.49,1.91),.27,.025,"gold",axis="X")
    for j in range(9):
        a=2*pi*j/9
        points=[]
        for r,t in ((.22,a),(.22,a+.20),(.15,a+.20),(.15,a+.38)):
            points.append((side*.738,-.49+cos(t)*r,1.91+sin(t)*r))
        tube(points,[.014]*4,"gold",sides=5,steps=1)
    pts=[]
    for j in range(26):
        t=j/25*3.8*pi;r=.02+.115*j/25
        pts.append((side*.743,-.49+cos(t)*r,1.91+sin(t)*r))
    tube(pts,[.013]*26,"gold",sides=5,steps=1)
    for j in (-1,1):
        end=(side*.65,-.49+j*.17,1.40)
        tube([(side*.65,-.49+j*.17,1.67),end],[.010,.010],"gold",sides=5)
        leaf(end,(side*.68,end[1],1.17),.07,"gold","body",False)
    # Turn the shoulder plates forward so both front and side views show relief.
    for i in range(first,len(V)):
        p=Vector(V[i])-Vector(center);t=-side*.55
        V[i]=tuple(Vector(center)+Vector((cos(t)*p.x-sin(t)*p.y,sin(t)*p.x+cos(t)*p.y,p.z)))
def crown():
    for side in (-1,1):
        main=[(side*.18,-.75,3.39),(side*.42,-.62,3.65),(side*.35,-.56,3.94),
              (side*.70,-.44,4.14),(side*.60,-.28,4.43),(side*.84,-.24,4.67)]
        tube(main,[.135,.14,.12,.10,.065,.022],"bark","head",12,7,.10)
        tips=[]
        for k in range(4):
            a=main[k+1];end=(side*(1.20+.30*k),-.57+.17*(k%2),3.86+k*.19+.10*sin(k*2.1))
            branch=[a,(side*(.74+.25*k),-.65,3.60+k*.20+.12*sin(k*2.4)),
                    (side*(1.02+.28*k),-.53,3.69+k*.17-.13*sin(k*2.4)),end]
            tube(branch,[.10-.012*k,.075,.05,.009],"bark","head",10,6,.08)
            tips.append(end)
            for turn in (-1,1):
                p=branch[2];tip=(p[0]+side*.16,p[1]+turn*.22,p[2]+.25)
                tube([p,tip],[.035,.006],"bark","head",8,5)
                tips.append(tip)
        tips.extend(main[3:])
        for q,tip in enumerate(tips):
            # Fan-shaped rounded leaf rosettes instead of sparse triangles.
            for petal in range(5):
                t=pi*.18+petal*pi*.18
                leaf(tip,(tip[0]+cos(t)*.32,tip[1]-.03+sin(t)*.08,tip[2]+sin(t)*.28),
                     .125,("jade","leaf","leaflight")[(q+petal)%3],"head",petal==2)
            if q%2==0:
                flower=(tip[0]+.04,tip[1]-.07,tip[2]-.08)
                for j in range(5):
                    a=j*2*pi/5
                    ell((flower[0]+cos(a)*.04,flower[1],flower[2]+sin(a)*.04),
                        (.034,.024,.034),"gold","head",8,6)
                ell(flower,(.025,.03,.025),"white","head",8,6)
            if q in (0,3,6):
                end=(tip[0],tip[1],tip[2]-.38)
                tube([tip,end],[.009,.009],"gold","head",5,2)
                leaf(end,(end[0],end[1],end[2]-.23),.08,"jade","head")
                ell((end[0],end[1],end[2]-.27),(.03,.03,.05),"gold","head",8,6)
        # Raised grain follows the antler's twists.
        for strand in range(2):
            offset=.045*(strand*2-1)
            pts=[(p[0]+offset,p[1]-.07,p[2]) for p in main]
            tube(pts,[.008,.012,.011,.008,.004,.001],"grain","head",5,5)
def anatomy():
    ell((0,.32,1.38),(.66,1.04,.61),"bark",seg=32,rings=20)
    ell((0,-.40,1.67),(.54,.57,.69),"bark",seg=28,rings=16)
    ell((0,-.65,2.16),(.40,.40,.72),"ivory","head",28,16)
    face_loft()
    # Small dark deer nose, engraved smile line, forehead bronze leaf.
    ell((0,-1.385,2.86),(.102,.052,.052),"hoof","head",16,8)
    for side in (-1,1):
        tube([(0,-1.38,2.82),(side*.075,-1.34,2.74),(side*.14,-1.28,2.77)],
             [.009,.011,.004],"groove","head",6,4)
        leaf((side*.24,-.79,3.35),(side*.93,-.69,3.56),.19,"ivory","head",False)
        leaf((side*.31,-.825,3.38),(side*.81,-.75,3.55),.11,"jade","head",False)
        almond(side);armor(side)
        for idx,y in enumerate((-.54,.99)):
            bone=("front" if idx==0 else "rear")+("L" if side<0 else "R")
            x=side*.47
            tube([(x,y,1.36),(x+side*.025,y+.09,.92),(x,y-.02,.40),(x,y-.045,.16)],
                 [.19,.15,.11,.12],"ivory",bone,12,5)
            # Cloven rounded hoof halves with a real gap.
            hoof(x,y,bone)
            tube([(x,y-.015,.44),(x,y-.015,.55)],[.145,.155],"gold",bone,16,1)
            ring((x,y-.015,.41),.143,.027,"gold",bone)
            ring((x,y-.015,.58),.157,.023,"gold",bone)
            for j in range(8):
                a=j*2*pi/8
                pts=[(x+cos(a)*.15,y+sin(a)*.15,.42),
                     (x+cos(a+.20)*.17,y+sin(a+.20)*.17,.51),
                     (x+cos(a+.39)*.155,y+sin(a+.39)*.155,.57)]
                tube(pts,[.012,.015,.010],"gold",bone,5,2)
        # Whorled bark grain wraps the flank in concentric, flowing burls.
        for pattern in range(3):
            yc=.18+pattern*.37;zc=1.37+(pattern%2)*.13
            for line in range(3):
                pts=[]
                for j in range(25):
                    t=j/24*2*pi*1.3;r=.07+line*.065+.13*j/24
                    y=yc+cos(t)*r;z=zc+sin(t)*r
                    inside=1-((y-.32)/1.04)**2-((z-1.38)/.61)**2
                    if inside>.05:pts.append((side*(.66*sqrt(inside)+.006),y,z))
                if len(pts)>2:tube(pts,[.008]*len(pts),"grain",sides=5,steps=1)
    # Forehead ornament.
    for side in (-1,1):
        leaf((0,-1.09,3.30),(side*.10,-1.08,3.47),.045,"gold","head",False)
    # Dense overlapping leaf mantle, with staggered tapered ends.
    for row in range(8):
        for j in range(14):
            t=j*2*pi/14+row*.20
            rad=.33+.025*row;z=3.10-row*.22
            a=(cos(t)*rad,-.64+sin(t)*rad*.93,z)
            b=(cos(t)*(rad+.24),-.64+sin(t)*(rad+.24),z-.51)
            leaf(a,b,.135,("leaf","jade","leaf","leaflight")[(j+row)%4],"head",j%2==0)
    # Back moss, leaves and small flowers break up the silhouette.
    for j in range(20):
        y=-.10+j*.065;x=sin(j*2.4)*.22
        leaf((x,y,1.98),(x+sin(j)*.14,y+.23,1.86),.12,"leaf","body",j%4==0)
        if j%3==0:ell((x,y,1.96),(.11,.15,.05),"moss","body",10,6)
    tail=[(0,1.24,1.43),(.15,1.56,1.17),(.12,1.90,.85),(.32,2.18,.56),(.58,2.40,.48)]
    tube(tail,[.13,.11,.08,.06,.015],"bark","tail",10,6,.08)
    for j in range(10):
        t=j/9;p=catmull(tail,4)[min(16,int(t*16))]
        side=(-1)**j
        leaf(p,p+Vector((side*.28,.22,-.18)),.13,"jade" if j%2 else "leaf","tail",j%3==0)
    # A faceted heart lamp with a substantial bronze petal setting.
    p=Vector((0,-1.18,2.17));size=.32
    vs=[p+Vector((0,0,size)),p+Vector((size*.67,0,0)),p+Vector((0,0,-size)),
        p+Vector((-size*.67,0,0)),p+Vector((0,-.20,0)),p+Vector((0,.05,0))]
    patch(vs,[(i,(i+1)%4,4) for i in range(4)]+[((i+1)%4,i,5) for i in range(4)],
          [(0,0)]*6,"glow","head")
    ringpts=[vs[i]+Vector((0,-.015,0)) for i in (0,1,2,3,0)]
    tube(ringpts,[.023]*5,"gold","head",6,1)
    for side in (-1,1):
        for j in range(4):
            leaf((side*.04,-1.17,1.86+j*.09),
                 (side*(.24+.055*j),-1.19,2.00+j*.14),.09,"gold","head",False)
    for offset in (-.08,.08):
        tube([(offset,-1.32,2.32),(offset*.5,-1.38,2.17),(offset,-1.31,2.00)],
             [.009,.012,.003],"white","head",5,2)
def create_mesh_and_rig():
    mesh=bpy.data.meshes.new("Qierong sculpted game mesh")
    mesh.from_pydata(V,[],F);mesh.update()
    obj=bpy.data.objects.new("Game mesh",mesh);scene.collection.objects.link(obj)
    for mat in M:mesh.materials.append(mat)
    uv=mesh.uv_layers.new(name="UVMap")
    for i,poly in enumerate(mesh.polygons):
        poly.material_index=FM[i];poly.use_smooth=True
        for loop_id in poly.loop_indices:uv.data[loop_id].uv=UV[mesh.loops[loop_id].vertex_index]
    for bone in set(VG):
        group=obj.vertex_groups.new(name=bone)
        group.add([i for i,b in enumerate(VG) if b==bone],1,"REPLACE")
    global rig
    arm=bpy.data.armatures.new("Qierong articulated skeleton")
    rig=bpy.data.objects.new("QierongRig",arm);scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig;rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bones={"body":((0,0,.8),(0,0,1.5),None),"head":((0,-.5,1.7),(0,-.7,2.7),"body"),
           "tail":((0,1.1,1.3),(0,1.9,.8),"body"),
           "frontL":((-.47,-.54,1.2),(-.47,-.54,.3),"body"),
           "frontR":((.47,-.54,1.2),(.47,-.54,.3),"body"),
           "rearL":((-.47,.99,1.2),(-.47,.99,.3),"body"),
           "rearR":((.47,.99,1.2),(.47,.99,.3),"body")}
    for name,(head,tail,parent) in bones.items():
        b=arm.edit_bones.new(name);b.head=head;b.tail=tail
        if parent:b.parent=arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.parent=rig
    mod=obj.modifiers.new("Articulated deform","ARMATURE");mod.object=rig
    rig.animation_data_create()
    for clip,frames in (("Idle",73),("Walk",37),("Attack",31)):
        for b in rig.pose.bones:b.rotation_mode="XYZ";b.rotation_euler=(0,0,0)
        for f in range(1,frames+1,6):
            t=(f-1)/(frames-1)*2*pi
            for b in rig.pose.bones:
                a=0
                if clip=="Idle" and b.name=="head":a=sin(t)*.018
                if clip=="Walk" and b.name.startswith(("front","rear")):a=sin(t+(pi if b.name in ("frontR","rearL") else 0))*.18
                if clip=="Attack" and b.name=="head":a=-sin((f-1)/(frames-1)*pi)*.25
                b.rotation_euler.x=a;b.keyframe_insert("rotation_euler",frame=f,group=b.name)
        action=rig.animation_data.action;action.name=clip
        track=rig.animation_data.nla_tracks.new();track.name=clip
        track.strips.new(clip,1,action);rig.animation_data.action=None
    scene.frame_set(1)
    return obj
def build(publish=False):
    global scene,V,F,UV,FM,VG,M,MI
    V=[];F=[];UV=[];FM=[];VG=[];M=[];MI={}
    scene=bpy.data.scenes.new("Qierong Reference Match")
    bpy.context.window.scene=scene
    make_materials();anatomy();crown();obj=create_mesh_and_rig()
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(WORK/"b03-v2.glb"),export_format="GLB",use_selection=True,use_active_scene=True,
        export_animations=True,export_animation_mode="NLA_TRACKS",export_frame_range=False,
        export_materials="EXPORT",export_yup=True,export_extras=False)
    bpy.data.libraries.write(str(WORK/"b03-v2.blend"),{scene},compress=True)
    obj.data.calc_loop_triangles()
    metrics={"asset":"b03","revision":2,"triangles":len(obj.data.loop_triangles),"vertices":len(obj.data.vertices),
        "materials":len(set(FM)),"bones":7,"glb_bytes":(WORK/"b03-v2.glb").stat().st_size,
        "textures":["textures/qierong_bark_basecolor.png","textures/qierong_bark_normal.png"],
        "blender":bpy.app.version_string}
    (WORK/"b03-v2.metrics.json").write_text(json.dumps(metrics,indent=2))
    if publish:
        import shutil
        shutil.copy2(WORK/"b03-v2.glb",OUT/"b03.glb")
        shutil.copy2(WORK/"b03-v2.blend",OUT/"b03.blend")
        (OUT/"b03.metrics.json").write_text(json.dumps(metrics,indent=2))
    print("QIERONG_V2",json.dumps(metrics))
def setup_studio():
    global scene
    scene=bpy.context.scene
    # A warm studio with soft key and reflected fill, using the actual game mesh.
    world=bpy.data.worlds.new("Qierong warm studio");world.use_nodes=True;scene.world=world
    bg=next(n for n in world.node_tree.nodes if n.type=="BACKGROUND")
    bg.inputs["Color"].default_value=(.70,.66,.57,1);bg.inputs["Strength"].default_value=.30
    floor_mat=bpy.data.materials.new("Qierong studio sand");floor_mat.use_nodes=True
    bsdf=next(n for n in floor_mat.node_tree.nodes if n.type=="BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value=(*linear("dfd1b5"),1);bsdf.inputs["Roughness"].default_value=.85
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.01))
    bpy.context.object.name="STUDIO floor";bpy.context.object.data.materials.append(floor_mat)
    for loc,power,size in (((-3,-4,7),650,4),((4,-1,5),230,4),((1,4,6),650,3)):
        bpy.ops.object.light_add(type="AREA",location=loc)
        o=bpy.context.object;o.data.energy=power;o.data.shape="DISK";o.data.size=size
        o.rotation_euler=(Vector((0,0,2.3))-o.location).to_track_quat("-Z","Y").to_euler()
    bpy.ops.object.camera_add(location=(7,-10,5.5))
    camera=bpy.context.object;camera.data.type="ORTHO";camera.data.ortho_scale=5.65;scene.camera=camera
    scene.render.engine="CYCLES";scene.cycles.samples=32;scene.cycles.use_denoising=True
    scene.render.resolution_x=1100;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
    scene.view_settings.view_transform="AgX";scene.view_settings.exposure=-.25
    return camera
def render_views(quick=False):
    camera=setup_studio()
    if quick:scene.render.resolution_percentage=65;scene.cycles.samples=16
    for view,p in (("three-quarter",(7,-10,5.5)),("front",(0,-10,4.1)),("side",(10,0,4.0)),("back",(0,10,4.1))):
        if quick and view!="three-quarter":continue
        camera.location=p
        camera.rotation_euler=(Vector((0,.15,2.28))-camera.location).to_track_quat("-Z","Y").to_euler()
        scene.render.filepath=str(RENDER/("b03-"+view+("-draft" if quick else "")+".png"))
        bpy.ops.render.render(write_still=True)
    print("QIERONG_RENDER_DONE")
