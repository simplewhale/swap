module equity::coins{

    use aptos_framework::coin;
    use std::string;
    use aptos_framework::signer;

    const RESOURCE_ACCOUNT: address = @equity;
    const DEFAULT_ADMIN: address = @default_admin;

    const ERROR_NOT_ALLOW: u64 = 0;

    struct USDT has key,store{

    }

    struct HoldCap has key{
        balance_u: coin::Coin<USDT>
    }

    fun init_module(sender: &signer) {
        
        init(sender);
     }

    fun init( account: &signer){
        let (burn,freeze,mint) = coin::initialize<USDT>(
            account,
            string::utf8(b"Tether"),
            string::utf8(b"USDT"),
            6,
            true,
        );
        
        let coin_mint = coin::mint(1000000000000000000, &mint);

        coin::destroy_freeze_cap(freeze);
        coin::destroy_mint_cap(mint);
        coin::destroy_burn_cap(burn);

        move_to(account, HoldCap {
            balance_u : coin_mint
        });
    }

    public entry fun withdraw(account: &signer,amount: u64) acquires HoldCap{
        let account_addr = signer::address_of(account);
        assert!(account_addr == DEFAULT_ADMIN, ERROR_NOT_ALLOW);

        if(!coin::is_account_registered<USDT>(account_addr)){
            coin::register<USDT>(account);
        };
        let holdCap = borrow_global_mut<HoldCap>(RESOURCE_ACCOUNT);
        let withdrawCoin = coin::extract(&mut holdCap.balance_u, amount);
        coin::deposit(account_addr, withdrawCoin);
    }

}