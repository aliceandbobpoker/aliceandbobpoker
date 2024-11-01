module aliceandbobpoker::math {

    const MODULUS: u256 = 21888242871839275222246405745257275088548364400416034343698204186575808495617u256;
    const SCALAR_MODULUS: u256 = 2736030358979909402780800718157159386076813972158567259200215660948447373041u256;

    public fun reduce_scalar(scalar: u256): u256 {
        let reduced = scalar % SCALAR_MODULUS;
        reduced
    }

    public fun mod_inverse(a: u256): u256 {
        let lm = 1;
        let hm = 0;
        let low = a % MODULUS;
        let high = MODULUS;
        while (low > 1) {
            let r = high / low;
            let nm = submod(hm, mulmod(lm, r));
            let new = submod(high, mulmod(low, r));
            hm = lm;
            high = low;
            lm = nm;
            low = new;
        };
        let result;
        if (low == 1) {
            result = lm % MODULUS;
        } else {
            result = 0
        };
        result
    }


    public fun addmod_scalar(a: u256, b: u256): u256 {
        if (b == 0u256){
            a
        }
        else {
            b = SCALAR_MODULUS - b;
            if (a >= b) {
                a - b
            }
            else {
                SCALAR_MODULUS - b + a
            }
        }
    }

    public fun addmod(a: u256, b: u256): u256 {
        if (b == 0u256){
            a
        }
        else {
            b = MODULUS - b;
            if (a >= b) {
                a - b
            }
            else {
                MODULUS - b + a
            }
        }
    }

    public fun submod(a: u256, b: u256): u256 {
        if ( a >= b) {
            a - b
        } else {
            MODULUS - b + a
        }
    }

    public fun mulmod(a: u256, b: u256): u256 {
        let result = 0;
        let a = a % MODULUS;
        let b = b % MODULUS;
        while (b > 0) {
            if (b % 2 == 1) {
                result = addmod(result, a);
            };
            a = addmod(a, a);
            b = b >> 1;
            // b = b / 2;
        };
        result
    }
}