module equity::dao {
    use equity::ct;
    use equity::bankRoll;
    use equity::coins;
    use std::signer;  
    use std::vector;
    use std::option;
    use std::string::String;

    use aptos_std::simple_map;
    use aptos_framework::coin;
    use aptos_framework::timestamp;

    const RESOURCE_ACCOUNT: address = @equity;
    const DEV: address = @dev;
    const DEFAULT_ADMIN: address = @default_admin;

    const ERROR_NOT_ALLOW: u64 = 0;
    const ERROR_NOT_ADMIN: u64 = 3;
    const ERROR_NOT_TIME_YET: u64 = 13;
    const ERROR_NO_ENOUGH_BALANCE : u64 = 14;
    const ERROR_HAVE_NUM_MINT: u64 = 21;
    const ERROR_NOT_VOTER: u64 = 22;
    const ERROR_NOT_MINT: u64 = 23;
    const ERROR_HAVE_NUM_OPERATE: u64 = 24;
    const ERROR_NOT_OPERATE: u64 = 25;
    const ERROR_HAVE_ORDER_REFUND: u64 = 26;
    const ERROR_NOT_REFUND: u64 = 27;
    const ERROR_HAVE_COMPENSATE :u64 = 28;

    friend equity::commerce;
    
    struct DaoInfo<phantom X,phantom Y> has key {
        admin : address,
        balance_ct: coin::Coin<X>,
        balance_u: coin::Coin<Y>,
        operateAmount : u64,
        fundAmount : u64,
        bonusAmount : u64,
        havebonus : u64,
        bonusTime : u64,
    }

    struct Voters has key{
        map : simple_map::SimpleMap<address, bool>,
    }

    struct Mint has copy, drop, store{
        inVote : bool,
        voterNumber : u64,
        mintTokenAmount : u64,
    }

    struct Mints has key{
        map : simple_map::SimpleMap<u64, Mint>,
    }

    struct Refund has copy, drop, store{
        inRefund : bool,
        voterRefundNumber : u64,
        refundAmount : u64,
        canCompensate : bool,
    }

    struct Refunds has key{
         map : simple_map::SimpleMap<String, Refund>,
    }

    struct Operate has copy, drop, store{
        inOperate : bool,
        voterOperateNumber : u64,
        operateAddress : address,
        operateAmount : u64,
    }

    struct Operates has key{
        map : simple_map::SimpleMap<u64, Operate>,
    }

    struct Bonuses has key {
        map : simple_map::SimpleMap<address, u64>,
    }

    fun init_module(sender: &signer) {

        move_to(sender, DaoInfo {
            admin : DEFAULT_ADMIN,
            balance_ct: coin::zero<ct::CT>(),
            balance_u: coin::zero<coins::USDT>(),
            operateAmount : 0,
            fundAmount : 0,
            bonusAmount : 0,
            havebonus : 0,
            bonusTime : 30 * 24 * 60 * 60,
        });

         move_to(sender, Voters {
           map : simple_map::create<address, bool>(),
        });

        move_to(sender, Mints {
           map : simple_map::create<u64, Mint>(),
        });

        move_to(sender, Operates {
           map : simple_map::create<u64, Operate>(),
        });

         move_to(sender, Bonuses {
           map : simple_map::create<address, u64>(),
        });

         move_to(sender, Refunds {
           map : simple_map::create<String, Refund>(),
        });

    }

    //Users distribute dividends based on the proportion of coins held
    public (friend) fun getBonus(sender: &signer, balance : u64) acquires DaoInfo , Bonuses{
        let sender_addr = signer::address_of(sender);
        let dao_info = borrow_global_mut<DaoInfo<ct::CT,coins::USDT>>(RESOURCE_ACCOUNT);
        let bonuses = borrow_global_mut<Bonuses>(RESOURCE_ACCOUNT);
        if(simple_map::contains_key<address,u64>(&bonuses.map , &sender_addr)){
            assert!(*simple_map::borrow<address,u64>(&bonuses.map , &sender_addr) + dao_info.bonusTime <= timestamp::now_seconds(),ERROR_NOT_TIME_YET);
            
            //update bonus timestamp.
            *simple_map::borrow_mut<address,u64>(&mut bonuses.map , &sender_addr) = timestamp::now_seconds();
        }else{
            
            //first time to bounus.
            simple_map::add(&mut bonuses.map, sender_addr , timestamp::now_seconds());
        };
        
        //pledge nft token amount + balanceof user
        balance = balance + coin::balance<ct::CT>(sender_addr);
        assert!(balance > 0 , ERROR_NO_ENOUGH_BALANCE);

        let supply = coin::supply<ct::CT>();
        let total = *option::borrow<u128>(&supply);

        //Calculate the number of divisible tokens
        let pay1 = (dao_info.bonusAmount as u128) * (balance as u128) / total;
        let pay = (pay1 as u64);
        assert!(pay + dao_info.havebonus <= dao_info.bonusAmount, ERROR_NO_ENOUGH_BALANCE);
        dao_info.havebonus = dao_info.havebonus + pay;

        let bonusCoin = coin::extract(&mut dao_info.balance_u, pay);
        coin::deposit(sender_addr , bonusCoin);
        
    }

    //Project party applies for team expense voting
    public entry fun operate(sender: &signer, num : u64) acquires Voters , Operates , DaoInfo{
        let sender_addr = signer::address_of(sender);
        let voters = borrow_global<Voters>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<address,bool>(&voters.map, &sender_addr), ERROR_NOT_VOTER);
        assert!(*simple_map::borrow<address,bool>(&voters.map, &sender_addr), ERROR_NOT_VOTER);

        let operates = borrow_global_mut<Operates>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<u64,Operate>(&operates.map, &num),ERROR_NOT_OPERATE);
        
        let operate = simple_map::borrow_mut(&mut operates.map, &num);
        assert!(operate.inOperate , ERROR_NOT_OPERATE);

        operate.voterOperateNumber = operate.voterOperateNumber + 1;
        if(operate.voterOperateNumber > simple_map::length(&voters.map) / 2){

            let dao_info = borrow_global_mut<DaoInfo<ct::CT,coins::USDT>>(RESOURCE_ACCOUNT);
            assert!(dao_info.operateAmount >= operate.operateAmount , ERROR_NO_ENOUGH_BALANCE);

            dao_info.operateAmount = dao_info.operateAmount - operate.operateAmount;
            let operateCoin = coin::extract(&mut dao_info.balance_u , operate.operateAmount);
            coin::deposit(operate.operateAddress , operateCoin);
            operate.inOperate = false; 
        }
    }

    //Administrators set project application team expense parameters
    public entry fun setOperate(sender: &signer, num : u64 , to : address , amount : u64) acquires DaoInfo , Operates{
        let dao_info = borrow_global<DaoInfo<ct::CT,coins::USDT>>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(dao_info.admin == sender_addr,ERROR_NOT_ADMIN);
        assert!(dao_info.operateAmount >= amount , ERROR_NO_ENOUGH_BALANCE);

        let operates = borrow_global_mut<Operates>(RESOURCE_ACCOUNT);
        assert!(!simple_map::contains_key<u64 , Operate>(&operates.map , &num) , ERROR_HAVE_NUM_OPERATE);
        simple_map::add(&mut operates.map, num, Operate{
            inOperate : true,
            voterOperateNumber : 0,
            operateAddress : to,
            operateAmount : amount,
        });  
       
    }

    //Voting for additional token issuance
    public entry fun mint(sender: &signer, num : u64) acquires  Mints , Voters{
        let sender_addr = signer::address_of(sender);
        let voters = borrow_global<Voters>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<address,bool>(&voters.map , &sender_addr), ERROR_NOT_VOTER);
        assert!(*simple_map::borrow<address,bool>(&voters.map , &sender_addr), ERROR_NOT_VOTER);

        let mints = borrow_global_mut<Mints>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<u64,Mint>(&mints.map, &num), ERROR_NOT_MINT);
        let mint = simple_map::borrow_mut(&mut mints.map, &num);
        assert!(mint.inVote , ERROR_NOT_MINT);

        mint.voterNumber = mint.voterNumber + 1;
        if(mint.voterNumber > simple_map::length(&voters.map) / 2){

            let mintCoin = ct::mint(mint.mintTokenAmount);
            bankRoll::deposit_ct(mintCoin);
            mint.inVote = false;
        }
    }

    //Administrator sets up mint token voting parameters.
    public entry fun setMintTokenAmount(sender: &signer, num : u64, amount : u64) acquires DaoInfo , Mints{
        let dao_info = borrow_global<DaoInfo<ct::CT,coins::USDT>>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(dao_info.admin == sender_addr,ERROR_NOT_ADMIN);

        let mints = borrow_global_mut<Mints>(RESOURCE_ACCOUNT);
        assert!(!simple_map::contains_key<u64,Mint>(&mints.map,&num), ERROR_HAVE_NUM_MINT);
        simple_map::add(&mut mints.map, num, Mint{
            inVote : true,
            voterNumber : 0,
            mintTokenAmount : amount,
        });  
    }

    //Query compensation amount based on refund order id
    public (friend) fun compensate(order : String) : coin::Coin<coins::USDT> acquires DaoInfo ,Refunds{
        let dao_info = borrow_global_mut<DaoInfo<ct::CT,coins::USDT>>(RESOURCE_ACCOUNT);
       
        let refunds = borrow_global_mut<Refunds>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<String,Refund>(&refunds.map, &order),ERROR_NOT_REFUND);
        let refund = simple_map::borrow_mut(&mut refunds.map, &order);

        let amount = refund.refundAmount;
        assert!(dao_info.fundAmount >= amount,ERROR_NO_ENOUGH_BALANCE);
        assert!(refund.canCompensate, ERROR_HAVE_COMPENSATE);
        refund.canCompensate = false;
        dao_info.fundAmount = dao_info.fundAmount - amount;

        let compensateCoin = coin::extract(&mut dao_info.balance_u, amount);
        compensateCoin
    }

    //More than half of the members of the DAO organization vote, can order compensation
    public (friend) fun refund(sender: &signer, order : String) : u64 acquires Refunds , Voters{
        let sender_addr = signer::address_of(sender);
        let voters = borrow_global<Voters>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<address,bool>(&voters.map , &sender_addr), ERROR_NOT_VOTER);
        assert!(*simple_map::borrow<address,bool>(&voters.map , &sender_addr), ERROR_NOT_VOTER);

        let refunds = borrow_global_mut<Refunds>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<String,Refund>(&refunds.map, &order),ERROR_NOT_REFUND);
        let refund = simple_map::borrow_mut(&mut refunds.map, &order);
        assert!(refund.inRefund , ERROR_NOT_REFUND);

        refund.voterRefundNumber = refund.voterRefundNumber + 1;
        if(refund.voterRefundNumber > simple_map::length(&voters.map) / 2){

            refund.inRefund = false;
            refund.canCompensate = true;
            return refund.refundAmount
        };
        0
    }

    //Administrator sets arbitration order parameters
     public entry fun setRefundAmount(sender: &signer, order : String, amount : u64) acquires DaoInfo , Refunds{
        let dao_info = borrow_global<DaoInfo<ct::CT,coins::USDT>>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(dao_info.admin == sender_addr, ERROR_NOT_ADMIN);

        let refunds = borrow_global_mut<Refunds>(RESOURCE_ACCOUNT);
        assert!(!simple_map::contains_key<String,Refund>(&refunds.map,&order), ERROR_HAVE_ORDER_REFUND);
        simple_map::add(&mut refunds.map, order , Refund{
            inRefund : true,
            voterRefundNumber : 0,
            refundAmount : amount,
            canCompensate : false,
        });  
        
    }

    //Administrator adds organizational members
    public entry fun setVoters(sender: &signer, arr : vector<address>) acquires DaoInfo, Voters{ 
        let dao_info = borrow_global<DaoInfo<ct::CT,coins::USDT>>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(dao_info.admin == sender_addr,ERROR_NOT_ADMIN);

        let voters = borrow_global_mut<Voters>(RESOURCE_ACCOUNT);
        let leng = vector::length(&arr);
        let i = 0;
        while (i < leng) {
            let voter = *vector::borrow<address>(&arr, i);
            if(simple_map::contains_key<address,bool>(&voters.map,&voter)){
                *simple_map::borrow_mut(&mut voters.map, &voter) = true;
            }else{
                simple_map::add(&mut voters.map, voter, true);
            };
        };
    }

    //Administrator updates funding parameters
    //Suggest updating on a monthly basis or after community formulas
    public entry fun updateDaoAvg(sender: &signer) acquires DaoInfo{ 
        let dao_info = borrow_global_mut<DaoInfo<ct::CT,coins::USDT>>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(dao_info.admin == sender_addr,ERROR_NOT_ADMIN);

        let balance = coin::value(&dao_info.balance_u);
        dao_info.bonusAmount = balance * 90 /100;
        dao_info.fundAmount =  balance * 5 /100;
        dao_info.operateAmount = balance * 5 /100;
        dao_info.havebonus = 0;
    }


    public  fun deposit_usdt(amount: coin::Coin<coins::USDT>):bool acquires DaoInfo{
        let dao_info = borrow_global_mut<DaoInfo<ct::CT,coins::USDT>>(RESOURCE_ACCOUNT);
        coin::merge(&mut dao_info.balance_u,amount);
        true
        
    }
}