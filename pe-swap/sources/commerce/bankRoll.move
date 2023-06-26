module equity::bankRoll {
    use equity::ct;
    use aptos_framework::coin;

    const RESOURCE_ACCOUNT: address = @equity;

    const ERROR_NOT_ALLOW: u64 = 0;
    
    friend equity::commerce;
    friend equity::dao;

    struct BankRollInfo<phantom T> has key {
        balance_ct: coin::Coin<T>,
    }

    fun init_module(sender: &signer) {

        move_to(sender, BankRollInfo {

            balance_ct: coin::zero<ct::CT>(),
        });
    }


    public (friend) fun aridop(amount: u64) : coin::Coin<ct::CT> acquires BankRollInfo{
        let bankRoll_info = borrow_global_mut<BankRollInfo<ct::CT>>(RESOURCE_ACCOUNT);
        
        if(coin::value(&bankRoll_info.balance_ct) >= amount){
            let airdopcoin = coin::extract(&mut bankRoll_info.balance_ct, amount);
            return airdopcoin
        };
        coin::zero<ct::CT>()
    }


     public (friend) fun deposit_ct( amount: coin::Coin<ct::CT>):bool acquires BankRollInfo{
        let bankRoll_info = borrow_global_mut<BankRollInfo<ct::CT>>(RESOURCE_ACCOUNT);
        coin::merge(&mut bankRoll_info.balance_ct,amount);
        true
        
    }

    public entry fun deposit(sender: &signer, amount:u64) acquires BankRollInfo{
        let withdrawCoin = coin::withdraw<ct::CT>(sender, amount);
        let bankRoll_info = borrow_global_mut<BankRollInfo<ct::CT>>(RESOURCE_ACCOUNT);
        coin::merge(&mut bankRoll_info.balance_ct, withdrawCoin);
        
    }
}