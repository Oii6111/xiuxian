"""Deterministic Blender 4.5 production source. Run inside Blender via MCP.
All geometry is original; Sapling is the upstream Blender GPL plugin.
Z up, -Y forward; exported glTF becomes Godot Y up, -Z forward.
"""
import bpy, math, random, json
from mathutils import Vector
from pathlib import Path
from math import sin, cos, pi
BASE=Path(r"D:\Projects\Codex\xiuxian")
OUT=BASE/"assets"/"blender"
RENDER=BASE/"docs"/"screenshots"/"blender"
OUT.mkdir(parents=True,exist_ok=True)
RENDER.mkdir(parents=True,exist_ok=True)
random.seed(38)
PAL={"bark":("#594431",0.90,0),"ridge":("#937455",0.75,0),
     "jade":("#438A72",0.44,0),"leaf":("#639D78",0.60,0),
     "ivory":("#EFE3BE",0.50,0),"gold":("#CBA55F",0.34,0.68),
     "hoof":("#363D38",0.72,0),"eye":("#163C38",0.28,0),
     "glow":("#85E8DD",0.22,0),"coat":("#4DADC7",0.55,0),
     "skin":("#FFD3AB",0.53,0),"hair":("#29364B",0.52,0),
     "roof":("#367D81",0.62,0),"stone":("#A4B7AB",0.84,0)}
MATS={}
rig=None
parts=[]
def reset():
    global MATS,parts,rig
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.data.orphans_purge(do_recursive=True)
    MATS={};parts=[];rig=None
    for name,(hx,rough,metal) in PAL.items():
        m=bpy.data.materials.new(name)
        srgb=tuple(int(hx[i:i+2],16)/255 for i in (1,3,5))
        linear=tuple(c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in srgb)
        m.diffuse_color=(*linear,1)
        m.use_nodes=True
        n=m.node_tree.nodes.get("Principled BSDF")
        n.inputs["Base Color"].default_value=m.diffuse_color
        n.inputs["Roughness"].default_value=rough
        n.inputs["Metallic"].default_value=metal
        if name=="glow":
            n.inputs["Emission Color"].default_value=m.diffuse_color
            n.inputs["Emission Strength"].default_value=0.55
        MATS[name]=m
def finish(o,name,mat,bone="body",bevel=0):
    o.name=name
    o.data.materials.clear();o.data.materials.append(MATS[mat])
    bpy.context.view_layer.objects.active=o
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        m=o.modifiers.new("Crafted round edges","BEVEL");m.width=bevel;m.segments=2
        bpy.ops.object.modifier_apply(modifier=m.name)
    if o.type=="MESH":
        for f in o.data.polygons:f.use_smooth=True
    o["rig_group"]=bone
    parts.append(o)
    return o
def ell(name,p,s,mat,bone="body",segments=24,rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=p)
    o=bpy.context.object;o.scale=s
    return finish(o,name,mat,bone)
def block(name,p,s,mat,bone="body",bevel=.06):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p)
    o=bpy.context.object;o.scale=s
    return finish(o,name,mat,bone,bevel)
def tube(name,points,radii,mat,bone="body",sides=8):
    verts=[];faces=[]
    for i,p in enumerate(points):
        p=Vector(p)
        direction=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        direction.normalize()
        u=direction.cross(Vector((0,1,0)))
        if u.length<.01:u=direction.cross(Vector((1,0,0)))
        u.normalize();v=direction.cross(u).normalized()
        for j in range(sides):
            q=p+radii[i]*(cos(j*2*pi/sides)*u+sin(j*2*pi/sides)*v)
            verts.append(tuple(q))
    for i in range(len(points)-1):
        for j in range(sides):
            a=i*sides+j;b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.extend([tuple(reversed(range(sides))),tuple((len(points)-1)*sides+j for j in range(sides))])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o)
    return finish(o,name,mat,bone)
def leaf(name,start,end,width,mat="jade",bone="head"):
    a=Vector(start);b=Vector(end);d=b-a
    u=d.cross(Vector((0,1,0)))
    if u.length<.01:u=d.cross(Vector((1,0,0)))
    u.normalize()
    v=d.cross(u).normalized()
    pts=[a,a+d*.30-u*width*.72,a+d*.64-u*width*.62,b,
         a+d*.64+u*width*.62,a+d*.30+u*width*.72,a+d*.48-v*width*.24,
         a+d*.48+v*width*.12]
    faces=[(0,1,6),(1,2,6),(2,3,6),(3,4,6),(4,5,6),(5,0,6),
           (1,0,7),(2,1,7),(3,2,7),(4,3,7),(5,4,7),(0,5,7)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([tuple(p) for p in pts],[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o)
    return finish(o,name,mat,bone,.008)
def torus(name,p,major,minor,mat,bone="body",rot=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=32,minor_segments=6,location=p,
        major_radius=major,minor_radius=minor,rotation=rot)
    return finish(bpy.context.object,name,mat,bone)
def gem(p,size,bone="head"):
    x,y,z=p
    verts=[(x,y-.09,z+size),(x+size*.67,y,z),(x,y-.09,z-size),
           (x-size*.67,y,z),(x,y-.30,z),(x,y+.05,z)]
    faces=[(i,(i+1)%4,4) for i in range(4)]+[((i+1)%4,i,5) for i in range(4)]
    mesh=bpy.data.meshes.new("Cut jade");mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new("Chest lantern gem",mesh);bpy.context.collection.objects.link(o)
    return finish(o,o.name,"glow",bone)
def deer():
    import runpy
    source=BASE/"tools"/"blender"/"refine_qierong.py"
    runpy.run_path(str(source))["build"](publish=True)

def deer_blockout():

    reset()
    ell("Carved wooden flank",(0,.30,1.30),(.72,1.06,.64),"bark")
    ell("Raised withers",(0,-.39,1.67),(.59,.58,.75),"bark")
    ell("Jade neck",(0,-.70,1.98),(.48,.43,.70),"ivory","head")
    ell("Deer face",(0,-.85,2.70),(.37,.37,.51),"ivory","head")
    ell("Tapered muzzle",(0,-1.12,2.47),(.25,.30,.22),"ivory","head")
    ell("Soft nose",(0,-1.38,2.52),(.13,.07,.075),"hoof","head")
    for side in (-1,1):
        leaf("Outer ear",(side*.25,-.77,2.94),(side*.91,-.70,3.15),.25,"ivory")
        leaf("Inner ear",(side*.34,-.80,2.98),(side*.79,-.76,3.13),.14,"jade")
        eye=ell("Almond eye",(side*.275,-1.09,2.76),(.105,.055,.13),"eye","head")
        eye.rotation_euler[1]=side*-.25
        ell("Eye jade iris",(side*.29,-1.136,2.77),(.060,.024,.086),"jade","head",16,8)
        ell("Eye highlight",(side*.28,-1.157,2.81),(.021,.011,.025),"ivory","head",12,8)
        tube("Brow ridge",[(side*.14,-1.1,2.90),(side*.28,-1.1,2.96),(side*.41,-.98,2.93)],
             [.025,.04,.012],"jade","head")
        for idx,y in enumerate((-.52,.99)):
            bone=("front" if idx==0 else "rear")+("L" if side<0 else "R")
            x=side*.49
            tube("Tapered deer leg",[(x,y,1.20),(x+side*.04,y+.12,.73),(x,y-.03,.22)],
                 [.18,.135,.115],"ivory",bone,12)
            block("Split hoof",(x,y-.07,.13),(.30,.38,.25),"hoof",bone,.065)
            tube("Hoof cleft",[(x,y-.267,.03),(x,y-.267,.22)],[.012,.012],"bark",bone,6)
            torus("Bronze anklet",(x,y,.40),.15,.043,"gold",bone)
            for j in range(3):
                leaf("Cuff petal",(x+side*.13,y-.08+j*.07,.37),
                     (x+side*.17,y-.09+j*.07,.59),.07,"gold",bone)
        # Shoulder seal, spiral bronze motif, legible at gameplay scale.
        torus("Shoulder medallion",(side*.62,-.53,1.85),.255,.043,"gold","body",(0,pi/2,0))
        pts=[]
        for j in range(29):
            t=j/28*4*pi;r=.025+.17*j/28
            pts.append((side*.66,-.53+cos(t)*r,1.85+sin(t)*r))
        tube("Seal spiral",pts,[.018]*len(pts),"gold")
    # Swept bark grain is actual geometry, not unsupported procedural texture.
    for side in (-1,1):
        for row in range(5):
            z=1.04+row*.15
            tube("Bark grain",[(side*.64,-.35,z),(side*.73,.05,z+.12),
                (side*.71,.48,z+.15),(side*.48,1.05,z+.08)],
                [.014,.022,.019,.006],"ridge")
    # Layered leaf mantle over neck; leaves overlap like Chinese feathered shawl.
    for layer in range(4):
        for j in range(12):
            a=2*pi*j/12
            r=.36+layer*.035;z=2.62-layer*.24
            start=(cos(a)*r,-.64+sin(a)*r*.88,z)
            end=(cos(a)*(r+.27),-.64+sin(a)*(r+.25),z-.55)
            leaf("Layered leaf mane",start,end,.18,"jade" if (j+layer)%3 else "leaf")
    # Dorsal leaves and articulated root tail.
    for j in range(7):
        leaf("Back foliage",(0,-.05+j*.18,1.95),(0,.10+j*.18,1.76),.21,"leaf","body")
    tail=[(0,1.16,1.42),(.2,1.55,1.17),(.12,1.83,.82),(.35,2.05,.48),(.50,2.36,.39)]
    tube("Root tail",tail,[.12,.10,.08,.06,.015],"bark","tail")
    for j,p in enumerate(tail[1:]):
        leaf("Tail leaf",p,(p[0]+(-1)**j*.34,p[1]+.27,p[2]-.13),.14,"jade","tail")
    # Deliberately designed antler silhouette; branches taper and arc upward.
    for side in (-1,1):
        trunk=[(side*.20,-.66,3.04),(side*.42,-.61,3.37),(side*.62,-.57,3.65),
               (side*.63,-.48,4.0),(side*.79,-.44,4.23)]
        tube("Tree antler",trunk,[.13,.115,.085,.055,.018],"bark","head",10)
        for k in range(3):
            a=trunk[k+1];sx=side*(.94+k*.28);z=3.48+k*.27
            end=(sx,-.59+(k%2)*.14,z+.18)
            tube("Antler fork",[a,(side*(.73+k*.21),-.61,z-.04),end],
                 [.075,.05,.012],"bark","head",8)
            for tip in (end,trunk[k+2]):
                for petal in range(5):
                    t=petal*2*pi/5
                    leaf("Crown leaf",tip,(tip[0]+cos(t)*.25,tip[1]+sin(t)*.18,tip[2]+.17),.12,"leaf")
                ell("Golden blossom",(tip[0],tip[1]-.03,tip[2]+.12),(.055,.055,.055),"gold","head",12,8)
            if k in (1,2):
                tube("Hanging bronze chain",[end,(end[0],end[1],end[2]-.25)],[.012,.012],"gold","head",6)
                leaf("Jade pendant",(end[0],end[1],end[2]-.22),(end[0],end[1],end[2]-.48),.09)
    gem((0,-1.20,1.94),.31)
    for side in (-1,1):
        for j in range(3):
            leaf("Chest gold setting",(0,-1.12,1.65+j*.10),
                (side*(.34+.08*j),-1.12,1.84+j*.17),.11,"gold")
    skeleton({"body":((0,0,.8),(0,0,1.5),None),
              "head":((0,-.5,1.7),(0,-.7,2.7),"body"),
              "tail":((0,1.1,1.3),(0,1.9,.8),"body"),
              "frontL":((-.49,-.52,1.2),(-.49,-.52,.3),"body"),
              "frontR":((.49,-.52,1.2),(.49,-.52,.3),"body"),
              "rearL":((-.49,.99,1.2),(-.49,.99,.3),"body"),
              "rearR":((.49,.99,1.2),(.49,.99,.3),"body")})
    export("b03",animated=True)
def skeleton(bones):
    global rig,parts
    arm=bpy.data.armatures.new("Articulated game rig")
    rig=bpy.data.objects.new("Rig",arm);bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True);bpy.ops.object.mode_set(mode="EDIT")
    for name,(head,tail,parent) in bones.items():
        b=arm.edit_bones.new(name);b.head=head;b.tail=tail
        if parent:b.parent=arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        if o.type!="MESH":continue
        g=o.vertex_groups.new(name=o["rig_group"])
        g.add(list(range(len(o.data.vertices))),1,"REPLACE")
        o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    mesh=bpy.context.object;mesh.name="Game mesh"
    mod=mesh.modifiers.new("Rigid articulated skeleton","ARMATURE");mod.object=rig
    mesh.parent=rig;parts=[mesh]
    # glTF exports named actions via NLA; clips never depend on a Blender driver.
    rig.animation_data_create()
    for clip,frames in (("Idle",72),("Walk",36),("Attack",30)):
        for b in rig.pose.bones:
            b.rotation_mode="XYZ";b.rotation_euler=(0,0,0)
        for f in range(1,frames+1,6):
            t=(f-1)/(frames-1)*2*pi
            for b in rig.pose.bones:
                angle=0
                if clip=="Idle" and b.name=="head":angle=sin(t)*.025
                if clip=="Walk" and b.name.startswith(("front","rear")):
                    angle=sin(t+(pi if b.name in ("frontR","rearL") else 0))*.20
                if clip=="Attack" and b.name=="head":angle=-sin((f-1)/(frames-1)*pi)*.32
                b.rotation_euler.x=angle;b.keyframe_insert("rotation_euler",frame=f,group=b.name)
        action=rig.animation_data.action;action.name=clip
        track=rig.animation_data.nla_tracks.new();track.name=clip
        track.strips.new(clip,1,action);rig.animation_data.action=None
    for b in rig.pose.bones:b.rotation_euler=(0,0,0)
    bpy.context.scene.frame_set(1)
def export(name,animated=False):
    bpy.ops.object.select_all(action="DESELECT")
    game=[o for o in bpy.context.scene.objects if o.type in ("MESH","ARMATURE","CURVE")]
    for o in game:
        if o.type=="CURVE":
            bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target="MESH");o.select_set(False)
    for o in bpy.context.scene.objects:
        if o.type in ("MESH","ARMATURE"):o.select_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(name+".blend")),check_existing=False)
    if not animated:
        bpy.context.view_layer.objects.active=next(o for o in bpy.context.scene.objects if o.type=="MESH")
        bpy.ops.object.join()
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,
        export_animations=animated,export_animation_mode="NLA_TRACKS",export_frame_range=False,
        export_materials="EXPORT",export_yup=True)
    tris=0;verts=0
    for o in bpy.context.scene.objects:
        if o.type=="MESH":
            o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);verts+=len(o.data.vertices)
    stat={"asset":name,"triangles":tris,"vertices":verts,"materials":len({m.name for o in bpy.context.scene.objects if o.type=="MESH" for m in o.data.materials if m}),"blender":bpy.app.version_string,"glb_bytes":(OUT/(name+".glb")).stat().st_size}
    (OUT/(name+".metrics.json")).write_text(json.dumps(stat,indent=2))
    print("ASSET_EXPORTED",json.dumps(stat))
def sapling():
    reset()
    before=set(bpy.data.objects)
    bpy.ops.curve.tree_add(seed=18,levels=3,scale=6.0,showLeaves=True,leaves=20,bevel=True,bevelRes=1,resU=3)
    created=[o for o in bpy.context.scene.objects if o not in before]
    for o in created:
        o.data.materials.clear();o.data.materials.append(MATS["jade" if o.type=="MESH" else "bark"])
        if o.type=="CURVE":o.data.resolution_u=2
    export("sapling_tree")
def pagoda():
    reset()
    block("Foundation",(0,0,.16),(3.6,3.4,.32),"stone",bevel=.13)
    block("Upper plinth",(0,0,.40),(3.15,2.95,.20),"ivory",bevel=.08)
    for z,span in ((1.52,1.15),(2.87,.85)):
        for x in (-span,span):
            for y in (-span,span):
                tube("Vermilion pillar",[(x,y,z-.98),(x,y,z+.40)],[.09,.08],"bark",sides=12)
                torus("Pillar bronze collar",(x,y,z-.86),.105,.025,"gold")
        block("Timber frame",(0,0,z+.25),(span*2.3,span*2.3,.22),"gold",bevel=.04)
        # Four curved tiled roof slopes with upswept corners.
        w=span+0.59;verts=[];faces=[];steps=10
        for side in range(4):
            offset=len(verts)
            for row in range(5):
                t=row/4;d=w*t
                for j in range(steps+1):
                    s=-1+2*j/steps
                    h=z+.98-.56*t+.22*t*t+abs(s)**4*.20*t*t
                    p=Vector((s*d,d,h))
                    p.rotate(__import__("mathutils").Matrix.Rotation(side*pi/2,4,"Z"))
                    verts.append(tuple(p))
            for row in range(4):
                for j in range(steps):
                    a=offset+row*(steps+1)+j;faces.append((a,a+1,a+steps+2,a+steps+1))
            for j in range(steps+1):
                pts=[]
                for row in range(5):
                    p=Vector(verts[offset+row*(steps+1)+j]);p.z+=.02;pts.append(tuple(p))
                tube("Roof tile ridge",pts,[.022]*5,"jade",sides=6)
        mesh=bpy.data.meshes.new("Curved roof");mesh.from_pydata(verts,[],faces);mesh.update()
        o=bpy.data.objects.new("Curved glazed roof",mesh);bpy.context.collection.objects.link(o)
        finish(o,o.name,"roof")
        for side in (-1,1):
            tube("Eave brass trim",[(-w,side*w,z+.84),(0,side*w,z+.64),(w,side*w,z+.84)],
                 [.035]*3,"gold",sides=6)
    torus("Lantern halo",(0,0,3.83),.20,.03,"gold")
    ell("Crown pearl",(0,0,3.96),(.14,.14,.18),"glow")
    for x in (-1.15,1.15):
        tube("Lantern chain",[(x,-1.15,1.90),(x,-1.15,1.57)],[.014,.014],"gold",sides=6)
        ell("Jade lantern",(x,-1.15,1.42),(.15,.15,.23),"glow")
        torus("Lantern cap",(x,-1.15,1.59),.10,.025,"gold")
    export("zhaosheng_pagoda")
def studio(asset="b03"):
    scene=bpy.context.scene
    scene.render.engine="CYCLES";scene.cycles.samples=24
    scene.render.resolution_x=960;scene.render.resolution_y=960;scene.render.resolution_percentage=100
    scene.world.color=(.34,.34,.34)
    scene.view_settings.view_transform="AgX"
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.025))
    floor=bpy.context.object;floor.name="STUDIO floor";floor.data.materials.append(MATS["ivory"])
    for loc,energy,size in (((-3,-5,7),800,5),((4,-1,5),550,4),((0,4,6),950,3)):
        bpy.ops.object.light_add(type="AREA",location=loc)
        o=bpy.context.object;o.data.energy=energy;o.data.shape="DISK";o.data.size=size
        o.rotation_euler=(Vector((0,0,1.8))-o.location).to_track_quat("-Z","Y").to_euler()
    bpy.ops.object.camera_add()
    camera=bpy.context.object;camera.data.type="ORTHO";camera.data.ortho_scale=5.4;scene.camera=camera
    for view,loc in (("front",(0,-10,3.9)),("side",(10,0,3.5)),("back",(0,10,3.9)),("three-quarter",(7,-9,5.4))):
        camera.location=loc
        camera.rotation_euler=(Vector((0,.2,2.0))-camera.location).to_track_quat("-Z","Y").to_euler()
        scene.render.filepath=str(RENDER/(asset+"-"+view+".png"))
        bpy.ops.render.render(write_still=True)
    print("RENDER_DONE",asset)
