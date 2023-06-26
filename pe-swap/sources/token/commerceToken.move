module equity::ct{

    use aptos_framework::coin;
    use std::string;
    use aptos_framework::signer;
    use aptos_framework::coin::{BurnCapability,MintCapability};

    friend equity::dao;

    const RESOURCE_ACCOUNT: address = @equity;
    const DEFAULT_ADMIN: address = @default_admin;

    const ERROR_NOT_ALLOW: u64 = 0;

    struct CT has key,store{

    }


    struct HoldCap has key{
        balance_ct: coin::Coin<CT>,
        mint: MintCapability<CT>,
        burn: BurnCapability<CT>,
    }

    fun init_module(sender: &signer) {
        
       init(sender,1000000000000000000,6);
    }

    fun init(account: &signer, total: u64, decimals: u8){
        let (burn,freeze,mint) = coin::initialize<CT>(
            account,
            string::utf8(b"CT"),
            string::utf8(b"CT"),
            decimals,
            true,
        );
        
        let coin_mint = coin::mint(total, &mint);
        
        coin::destroy_freeze_cap(freeze);
        
        move_to(account, HoldCap {
            balance_ct : coin_mint,
            mint : mint,
            burn : burn,
        });
    }

    public (friend) fun mint(amount : u64) : coin::Coin<CT>  acquires HoldCap{

        let holdCap = borrow_global<HoldCap>(RESOURCE_ACCOUNT);
        let mintCoin = coin::mint(amount, &holdCap.mint);
        mintCoin
    }

    public entry fun withdraw(account: &signer,amount: u64) acquires HoldCap{
        let account_addr = signer::address_of(account);
        assert!(account_addr == DEFAULT_ADMIN, ERROR_NOT_ALLOW);

        if(!coin::is_account_registered<CT>(account_addr)){
            coin::register<CT>(account);
        };
        let holdCap = borrow_global_mut<HoldCap>(RESOURCE_ACCOUNT);
        let withdrawCoin = coin::extract(&mut holdCap.balance_ct, amount);
        coin::deposit(account_addr, withdrawCoin);
    }

}