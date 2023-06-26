/// Uniswap v2 like token swap program
module equity::swap_utils {
    use std::string;
    use aptos_std::type_info;
    use aptos_std::comparator;
    use equity::math;


    const EQUAL: u8 = 0;
    const SMALLER: u8 = 1;
    const GREATER: u8 = 2;

    const ERROR_INSUFFICIENT_INPUT_AMOUNT: u64 = 0;
    const ERROR_INSUFFICIENT_LIQUIDITY: u64 = 1;
    const ERROR_INSUFFICIENT_AMOUNT: u64 = 2;
    const ERROR_INSUFFICIENT_OUTPOT_AMOUNT: u64 = 3;
    const ERROR_SAME_COIN: u64 = 4;
    const MAX_U64: u128 = 18446744073709551615;
    const MAX_U32: u128 = 4294967296;


   public fun gcd(a: u8,b: u8):u8 {
        while (b > 0) {
            let temp=b;
            b = a%b;
            a = temp;
        };
        a
    }
    
    #[view]
    public fun exp(n: u128,a: u8,b: u8):u128{
        let g = gcd(a,b);
        a = a/g;
        b = b/g;
        if(a ==b){
            n
        }else if(a == 1 && b == 2){
             math::sqrt(n * MAX_U64)
        }else if (a == 2 && b == 1) {
            n * n / MAX_U64
        }else if (a == 4 && b ==1) {
            n * n / MAX_U32 * n /  MAX_U32 * n /  MAX_U64
        }else if (b == 4 && a ==1) {
            math::sqrt( math::sqrt(n *  MAX_U64) *  MAX_U32)
        }else{
            n
        }
    }

    /*public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
    ): u64 {
        assert!(amount_in > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERROR_INSUFFICIENT_LIQUIDITY);

        let amount_in_with_fee = (amount_in as u128) * 997u128;
        let numerator = amount_in_with_fee * (reserve_out as u128);
        let denominator = (reserve_in as u128) * 1000u128 + amount_in_with_fee;
        ((numerator / denominator) as u64)
    }*/
    #[view]
     public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        expA: u8,
        expB: u8
    ): u64 {
        assert!(amount_in > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERROR_INSUFFICIENT_LIQUIDITY);

        // Round up the result of exp to make the output smaller
        let k = (exp((reserve_in as u128), expA, 100) + 1)*(exp((reserve_out as u128), expB, 100) + 1);
        // Here * 997/1000 will be taken down to make the output smaller
        let den = reserve_in + amount_in*997/1000;
        let denominator = exp((den as u128), expA, 100); 
        // Round up here to make the output smaller
        let tmp = (k + denominator-1)/denominator; 
        // Round up here to make the output smaller
        tmp = exp(tmp, 100, expB) + 1; 
        reserve_out - (tmp as u64)
    }

    /*public fun get_amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64
    ): u64 {
        assert!(amount_out > 0, ERROR_INSUFFICIENT_OUTPOT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERROR_INSUFFICIENT_LIQUIDITY);

        let numerator = (reserve_in as u128) * (amount_out as u128) * 10000u128;
        let denominator = ((reserve_out as u128) - (amount_out as u128)) * 9975u128;
        (((numerator / denominator) as u64) + 1u64)
    }*/

    public fun get_amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64,
        expA: u8,
        expB: u8
    ): u64 {
        assert!(amount_out > 0, ERROR_INSUFFICIENT_OUTPOT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERROR_INSUFFICIENT_LIQUIDITY);

        // Round up the result of exp to make the input larger
        let k = (exp((reserve_in as u128), expA, 100) + 1) * (exp((reserve_out as u128), expB, 100) + 1);
        // The exp result itself is rounded down, and the input becomes larger
        let denominator = exp((reserve_out as u128) - (amount_out as u128), expB, 100);
        // The result is rounded up to make the input larger
        let tmp = (k + denominator-1)/denominator;
        // The result is rounded up to make the input larger
        tmp = exp(tmp, 100, expA) + 1;
        tmp = tmp - (reserve_in as u128);
        // The result is rounded up to make the input larger
        ((tmp as u64) * 1000 + 996) / 997
    }

    public fun quote(amount_x: u64, reserve_x: u64, reserve_y: u64): u64 {
        assert!(amount_x > 0, ERROR_INSUFFICIENT_AMOUNT);
        assert!(reserve_x > 0 && reserve_y > 0, ERROR_INSUFFICIENT_LIQUIDITY);
        (((amount_x as u128) * (reserve_y as u128) / (reserve_x as u128)) as u64)
    }

    public fun get_token_info<T>(): vector<u8> {
        let type_name = type_info::type_name<T>();
        *string::bytes(&type_name)
    }

    // convert Struct to bytes ,then compare
    fun compare_struct<X, Y>(): u8 {
        let struct_x_bytes: vector<u8> = get_token_info<X>();
        let struct_y_bytes: vector<u8> = get_token_info<Y>();
        if (comparator::is_greater_than(&comparator::compare_u8_vector(struct_x_bytes, struct_y_bytes))) {
            GREATER
        } else if (comparator::is_equal(&comparator::compare_u8_vector(struct_x_bytes, struct_y_bytes))) {
            EQUAL
        } else {
            SMALLER
        }
    }

    public fun get_smaller_enum(): u8 {
        SMALLER
    }

    public fun get_greater_enum(): u8 {
        GREATER
    }

    public fun get_equal_enum(): u8 {
        EQUAL
    }

    public fun sort_token_type<X, Y>(): bool {
        let compare_x_y: u8 = compare_struct<X, Y>();
        assert!(compare_x_y != get_equal_enum(), ERROR_SAME_COIN);
        (compare_x_y == get_smaller_enum())
    }
}
