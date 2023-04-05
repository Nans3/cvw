#!/usr/bin/env python3

# Authors: Limnanthes Serafini (lserafini@hmc.edu) and Alec Vercruysse (avercruysse@hmc.edu)

import sys
import os

sys.path.append(os.path.expanduser("~/cvw/bin"))
import CacheSim as cs

if __name__ == "__main__":
    cache = cs.Cache(16, 4, 16, 8)
    # 0xABCD -> tag: AB, set: C, offset: D

    #address split checking
    assert (cache.splitaddr(0x1234) == (0x12,0x3,0x4))
    assert (cache.splitaddr(0x2638) == (0x26,0x3,0x8))
    assert (cache.splitaddr(0xA3E6) == (0xA3,0xE,0x6))
    
    #insert way 0 set C tag AB
    assert (cache.cacheaccess(0xABCD) == 'M')
    assert (cache.ways[0][0xC].tag == 0xAB)
    assert (cache.cacheaccess(0xABCD) == 'H')
    assert (cache.pLRU[0xC] == [1,1,0])

    #make way 0 set C dirty
    assert (cache.cacheaccess(0xABCD, True) == 'H')

    #insert way 1 set C tag AC 
    assert (cache.cacheaccess(0xACCD) == 'M')
    assert (cache.ways[1][0xC].tag == 0xAC)
    assert (cache.pLRU[0xC] == [1,0,0])

    #insert way 2 set C tag AD
    assert (cache.cacheaccess(0xADCD) == 'M')
    assert (cache.ways[2][0xC].tag == 0xAD)
    assert (cache.pLRU[0xC] == [0,0,1])

    #insert way 3 set C tag AE 
    assert (cache.cacheaccess(0xAECD) == 'M')
    assert (cache.ways[3][0xC].tag == 0xAE)
    assert (cache.pLRU[0xC] == [0,0,0])

    #misc hit and pLRU checking
    assert (cache.cacheaccess(0xABCD) == 'H')
    assert (cache.pLRU[0xC] == [1,1,0])
    assert (cache.cacheaccess(0xADCD) == 'H')
    assert (cache.pLRU[0xC] == [0,1,1])

    #evict way 1, now set C has tag AF
    assert (cache.cacheaccess(0xAFCD) == 'E')
    assert (cache.ways[1][0xC].tag == 0xAF)
    assert (cache.pLRU[0xC] == [1,0,1])

    #evict way 3, now set C has tag AC
    assert (cache.cacheaccess(0xACCD) == 'E')
    assert (cache.ways[3][0xC].tag == 0xAC)
    assert (cache.pLRU[0xC] == [0,0,0])

    #evict way 0, now set C has tag EA
    #this line was dirty, so there was a wb
    assert (cache.cacheaccess(0xEAC2) == 'D')
    assert (cache.ways[0][0xC].tag == 0xEA)
    assert (cache.pLRU[0xC] == [1,1,0])