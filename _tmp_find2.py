with open('_a3_probe_after7.txt','rb') as f:
    for i,line in enumerate(f,1):
        if b'laps(at)' in line:
            print(i, repr(line))
