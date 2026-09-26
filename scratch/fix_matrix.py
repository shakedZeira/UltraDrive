import math

mass=1200.0; R=0.33
tire_B=10.0; tire_C=1.9; tire_D=1.0; tire_E=0.97
grip=1.3; surf=1.0
max_torque=300.0; peak=6500.0; redline=7500.0; idle=800.0
ratios=[3.5,2.1,1.4,1.0,0.75,0.6]; final=3.7
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

def step_spin(omega, drive, brake, F, v, I_val):
    net=drive-brake-F*R
    den=max(abs(v)/R,1.0)
    sf=long_stiff(slip_ratio(omega,v),N)*R/(I_val*den)
    kd=max(-0.9,min(2000.0,sf*dt))
    damp=1.0/(1.0+kd); damp=max(0.0,min(1.0,damp))
    return omega+net*dt/I_val*damp

def drag(v): return 0.5*1.225*0.35*2.2*v*v

def release_timeline(v0, omega_r0, engine_rpm0, gr2, I_val, eb):
    v=v0; omega_r=omega_r0; omega_f=v/R; engine_rpm=engine_rpm0
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
        mag=eb*(brake_rpm/peak)
        drive=(-mag*abs(gr2))/2.0
        F_r=long_force(slip_ratio(omega_r,v),N)
        F_f=long_force(slip_ratio(omega_f,v),N)
        a=(2*F_r+2*F_f-drag(v))/mass
        v=v+a*dt
        omega_r=step_spin(omega_r,drive,0.0,F_r,v,I_val)
        omega_f=step_spin(omega_f,0.0,0.0,F_f,v,I_val)
        track.append((F_r,a,v,slip_ratio(omega_r,v)))
    f_F=next((i for i,t in enumerate(track) if t[0]<=0), None)
    f_a=next((i for i,t in enumerate(track) if t[1]<0), None)
    imp=sum(t[0]*2*dt for t in track if t[0]>0)
    return f_F, f_a, imp, track

def full_sim(gear_idx, release_after_s, I_val, eb, label):
    gr2=ratios[gear_idx-1]*final
    v=0.5
    engine_rpm=max(v/R*gr2*60/(2*math.pi), idle)
    omega_f=v/R; omega_r=v/R
    rel=int(release_after_s/dt)
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
    s0=slip_ratio(omega_r,v)
    f_F,f_a,imp,tr=release_timeline(v,omega_r,engine_rpm,gr2,I_val,eb)
    print("%-34s v=%.1f slip_start=%.3f  F_rear<=0@%-3s a<0@%-3s  posImp=%.0f N*s (dv=%.2f)  F_rear[0]=%.0f F_rear[5]=%.0f" % (
        label,v,s0, str(f_F+1) if f_F is not None else ">90", str(f_a+1) if f_a is not None else ">90", imp, imp/mass,
        tr[0][0], tr[5][0] if len(tr)>5 else float('nan')))

print("%-34s | release-pull timeline metrics" % "SCENARIO")
print("I=3.5 eb=50  BASELINE")
full_sim(1,0.5,3.5,50.0," launch g1 rel0.5s")
full_sim(1,0.2,3.5,50.0," launch g1 rel0.2s")
full_sim(2,0.8,3.5,50.0," accel g2 rel0.8s")
full_sim(2,1.5,3.5,50.0," accel g2 rel1.5s")
print("I=3.5 eb=150")
full_sim(1,0.5,3.5,150.0," launch g1 rel0.5s")
full_sim(2,0.8,3.5,150.0," accel g2 rel0.8s")
print("I=3.5 eb=250")
full_sim(1,0.5,3.5,250.0," launch g1 rel0.5s")
full_sim(2,0.8,3.5,250.0," accel g2 rel0.8s")
print("I=2.2 eb=150")
full_sim(1,0.5,2.2,150.0," launch g1 rel0.5s")
full_sim(2,0.8,2.2,150.0," accel g2 rel0.8s")
print("I=1.8 eb=150")
full_sim(1,0.5,1.8,150.0," launch g1 rel0.5s")
full_sim(2,0.8,1.8,150.0," accel g2 rel0.8s")