import math

# CarConfig starter numbers
mass=1200.0; R=0.33; I=3.5
tire_B=10.0; tire_C=1.9; tire_D=1.0; tire_E=0.97
grip=1.3; surf=1.0
max_torque=300.0; peak=6500.0; redline=7500.0; idle=800.0
eng_brake=50.0
ratios=[3.5,2.1,1.4,1.0,0.75,0.6]; final=3.7
gear=2; gr=ratios[gear-1]*final
dt=1/60
N=mass*9.8/4

def eng_t(rpm):
    if rpm<idle: return max_torque*0.5
    if rpm>redline: return 0.0
    if rpm<=peak:
        t=(rpm-idle)/(peak-idle); return max_torque*(0.5+0.5*t)
    t2=(rpm-peak)/(redline-peak); return max_torque*(1.0-t2*t2)

def slip_ratio(w,v):
    ws=w*R
    den=max(abs(ws),abs(v),1.0)
    return max(-1.0,min(1.0,(ws-v)/den))

def long_force(s,Nf):
    B=tire_B*0.8; C=tire_C; D=Nf*tire_D*grip*surf*0.95; E=tire_E
    x=s; bx=B*x
    return D*math.sin(C*math.atan(bx-E*(bx-math.atan(bx))))

def long_stiff(s,Nf):
    B=tire_B*0.8; C=tire_C; D=Nf*tire_D*grip*surf*0.95; E=tire_E
    x=s; bx=B*x; ab=math.atan(bx)
    g=bx-E*(bx-ab); w=C*math.atan(g)
    dg=B-E*(B-B/(1.0+bx*bx))
    return D*math.cos(w)*C/(1.0+g*g)*dg

def step_spin(omega, drive, brake, F, v, I_val=I):
    net=drive-brake-F*R
    den=max(abs(v)/R,1.0)
    sf=long_stiff(slip_ratio(omega,v),N)*R/(I_val*den)
    kd=max(-0.9,min(2000.0,sf*dt))
    damp=1.0/(1.0+kd); damp=max(0.0,min(1.0,damp))
    return omega+net*dt/I_val*damp

def drag(v): return 0.5*1.225*0.35*2.2*v*v

def sim(I_val, eng_brake_val, label):
    v=8.0
    engine_rpm=max(v/R*gr*60/(2*math.pi), idle)
    omega_f=v/R
    omega_r=v/R
    for _ in range(60*20):
        if v>=20.0: break
        rpm_from=v/R*gr*60/(2*math.pi)
        target=max(rpm_from,idle)
        step=peak*dt*2
        if engine_rpm<target: engine_rpm=min(engine_rpm+step,target)
        elif engine_rpm>target: engine_rpm=max(engine_rpm-step,target)
        eng=eng_t(engine_rpm)*1.0
        drive=eng*abs(gr)/2.0
        F_r=long_force(slip_ratio(omega_r,v),N)
        F_f=long_force(slip_ratio(omega_f,v),N)
        a=(2*F_r+2*F_f-drag(v))/mass
        v=v+a*dt
        omega_r=step_spin(omega_r,drive,0.0,F_r,v,I_val)
        omega_f=step_spin(omega_f,0.0,0.0,F_f,v,I_val)
    print("--- %s: v=%.2f m/s (%.1f km/h) slip=%.3f F_r=%.0f engine_rpm=%.0f" % (label,v,v*3.6,slip_ratio(omega_r,v),F_r,engine_rpm))
    track=[]
    for k in range(60):
        axle_speed=omega_r*R
        axle_rpm=axle_speed/R*gr*60/(2*math.pi)
        rpm_from=v/R*gr*60/(2*math.pi)
        target=max(rpm_from,idle)
        step=peak*dt*2
        if engine_rpm<target: engine_rpm=min(engine_rpm+step,target)
        elif engine_rpm>target: engine_rpm=max(engine_rpm-step,target)
        brake_rpm=max(engine_rpm,axle_rpm); brake_rpm=min(brake_rpm,redline); brake_rpm=max(brake_rpm,idle)
        mag=eng_brake_val*(brake_rpm/peak)
        drive=(-mag*abs(gr))/2.0
        F_r=long_force(slip_ratio(omega_r,v),N)
        F_f=long_force(slip_ratio(omega_f,v),N)
        a=(2*F_r+2*F_f-drag(v))/mass
        v=v+a*dt
        omega_r=step_spin(omega_r,drive,0.0,F_r,v,I_val)
        omega_f=step_spin(omega_f,0.0,0.0,F_f,v,I_val)
        track.append((k+1,drive,slip_ratio(omega_r,v),F_r,a,v,engine_rpm,brake_rpm))
    f_F=next((r[0] for r in track if r[3]<=0), None)
    f_a=next((r[0] for r in track if r[4]<0), None)
    imp=sum(r[3]*2 for r in track if r[3]>0)*dt
    for k in [1,2,3,5,10,20,60]:
        r=track[k-1]
        if k-1<len(track):
            print("  rel frame %2d: drive/wheel=%8.1f slip=%+.3f F_rear=%7.0f a=%+.2f v=%.2f brpm=%.0f" % (r[0],r[1],r[2],r[3],r[4],r[5],r[7]))
    print("  F_rear<=0 at frame %s | body a<0 at frame %s | pos impulse=%.0f N*s dv=%.2f m/s" % (f_F,f_a,imp,imp/mass))
    return track

def sim_launch(I_val, eng_brake_val, gear_idx, release_at_s, label):
    gr2=ratios[gear_idx-1]*final
    v=0.5
    engine_rpm=max((v/R*gr2*60/(2*math.pi), idle))
    omega_f=v/R
    omega_r=v/R
    rel=int(release_at_s/dt)
    # throttle on until rel frames
    for k in range(rel):
        rpm_from=v/R*gr2*60/(2*math.pi)
        target=max(rpm_from,idle)
        step=peak*dt*2
        if engine_rpm<target: engine_rpm=min(engine_rpm+step,target)
        elif engine_rpm>target: engine_rpm=max(engine_rpm-step,target)
        eng=eng_t(engine_rpm)*1.0
        drive=eng*abs(gr2)/2.0
        F_r=long_force(slip_ratio(omega_r,v),N)
        F_f=long_force(slip_ratio(omega_f,v),N)
        a=(2*F_r+2*F_f-drag(v))/mass
        v=v+a*dt
        omega_r=step_spin(omega_r,drive,0.0,F_r,v,I_val)
        omega_f=step_spin(omega_f,0.0,0.0,F_f,v,I_val)
    print("--- %s: at release v=%.2f m/s slip=%.3f F_r=%.0f omega_r=%.1f (rolling=%.1f) engine_rpm=%.0f" % (
        label,v,slip_ratio(omega_r,v),F_r,omega_r,v/R,engine_rpm))
    track=[]
    for k in range(90):
        axle_speed=omega_r*R
        axle_rpm=axle_speed/R*gr2*60/(2*math.pi)
        rpm_from=v/R*gr2*60/(2*math.pi)
        target=max(rpm_from,idle)
        step=peak*dt*2
        if engine_rpm<target: engine_rpm=min(engine_rpm+step,target)
        elif engine_rpm>target: engine_rpm=max(engine_rpm-step,target)
        brake_rpm=max(engine_rpm,axle_rpm); brake_rpm=min(brake_rpm,redline); brake_rpm=max(brake_rpm,idle)
        mag=eng_brake_val*(brake_rpm/peak)
        drive=(-mag*abs(gr2))/2.0
        F_r=long_force(slip_ratio(omega_r,v),N)
        F_f=long_force(slip_ratio(omega_f,v),N)
        a=(2*F_r+2*F_f-drag(v))/mass
        v=v+a*dt
        omega_r=step_spin(omega_r,drive,0.0,F_r,v,I_val)
        omega_f=step_spin(omega_f,0.0,0.0,F_f,v,I_val)
        track.append((k+1,drive,slip_ratio(omega_r,v),F_r,a,v,omega_r))
    f_F=next((r[0] for r in track if r[3]<=0), None)
    f_a=next((r[0] for r in track if r[4]<0), None)
    imp=sum(r[3]*2 for r in track if r[3]>0)*dt
    print("  rel frame %2d: drive/wheel=%8.1f slip=%+.3f F_rear=%7.0f a=%+.2f v=%.2f" % (track[0][0],track[0][1],track[0][2],track[0][3],track[0][4],track[0][5]))
    for k in [5,10,15,20,30,45,60]:
        r=track[k-1]
        print("  rel frame %2d: drive/wheel=%8.1f slip=%+.3f F_rear=%7.0f a=%+.2f v=%.2f" % (r[0],r[1],r[2],r[3],r[4],r[5]))
    print("  F_rear<=0 at frame %s | body a<0 at frame %s | pos impulse=%.0f N*s dv=%.2f m/s" % (f_F,f_a,imp,imp/mass))
    return track

print("BASELINE (I=3.5, eng_brake=50)")
baseline=sim(3.5,50.0,"baseline")
print()
print("STANDING LAUNCH gear1, releaseafter 0.5s")
t=sim_launch(3.5,50.0,1,0.5,"launch-g1")