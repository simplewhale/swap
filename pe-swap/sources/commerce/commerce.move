module equity::commerce {
    use equity::swap;
    use equity::dao;
    use equity::swap_utils;
    use equity::coins;
    use equity::bankRoll;
    use equity::ct;
    use equity::commerceNft;
    use std::signer;
    use aptos_framework::coin;
    use std::string::{Self, String};
    use aptos_std::simple_map;
    use std::vector;

    use aptos_framework::timestamp;

    const RESOURCE_ACCOUNT: address = @equity;
    const DEFAULT_ADMIN: address = @default_admin;
    const DEV: address = @dev;
    const ZERO: address = @zero;

    const ERROR_NOT_ALLOW: u64 = 0;
    const ERROR_ORDER_NOT_EXISTS: u64 = 2;
    const ERROR_NOT_ADMIN: u64 = 3;
    const ERROR_ORDER_EXISTS: u64 = 4;
    const ERROR_HAVE_INVITER: u64 = 5;
    const ERROR_NOT_BUYER: u64 = 6;
    const ERROR_HAVED_DELAY: u64 = 7;
    const ERROR_NO_BUYER: u64 = 8;
    const ERROR_SHARES_TOOBIG: u64 = 9;
    const ERROR_HAVE_CONFIRM: u64 = 10;
    const ERROR_HAVE_SELLED: u64 = 11;
    const ERROR_CANNOT_WITHDRAW: u64 = 12;
    const ERROR_NOT_TIME_YET: u64 = 13;
    const ERROR_NO_ENOUGH_BALANCE : u64 = 14;
    const ERROR_NO_PLEDGE : u64 = 15;

    struct Order has copy, drop, store {
        orderStatus: bool,
        orderName: String,
        orderPrice: u64,
        orderData: u64,
        orderDelay: bool,
        orderBusiness: address,
        orderPromoter1: address,
        orderPromoter2: address,
        orderBuyer: address,
        orderTaxation: address,
        orderConfirm: bool,
        orderNftId : u128,
    }

    struct Orders has key{
        map : simple_map::SimpleMap<String, Order>,
    }

    struct Shares has key{
        map : simple_map::SimpleMap<address, simple_map::SimpleMap<String,u64>>,
    }

    struct Profit has key{
        map : simple_map::SimpleMap<address, simple_map::SimpleMap<String,u64>>,
    }

    struct TaxationAvgs has key{
        map : simple_map::SimpleMap<address, u64>,
    }

    struct Pledges has key{
        map : simple_map::SimpleMap<address, u64>,
    }


    struct Inviter has key{
        inviter : address,
    }

    struct CommerceInfo has key {
        balance_u: coin::Coin<coins::USDT>,
        admin : address,
        time : u64,
    }

   

    fun init_module(sender: &signer) {
        
        move_to(sender, CommerceInfo {
            balance_u: coin::zero<coins::USDT>(),
            admin: DEFAULT_ADMIN,
            time: 15 * 24 * 60 * 60,
        });
        
        move_to(sender, Orders{
            map : simple_map::create<String, Order>(),
        });

        move_to(sender, Shares{
            map : simple_map::create<address, simple_map::SimpleMap<String,u64>>(),
        });

        move_to(sender, Profit{
            map : simple_map::create<address,simple_map::SimpleMap<String,u64>>(),
        });

        move_to(sender, TaxationAvgs{
            map : simple_map::create<address,u64>(),
        });

         move_to(sender, Pledges{
            map : simple_map::create<address, u64>(),
        });
    }

    //Users distribute dividends based on the proportion of coins held
    public entry fun getBonus(sender: &signer){
        let sender_addr = signer::address_of(sender);
        let nftBalance = commerceNft::getAddressTokenBalance(sender_addr);
        dao::getBonus(sender,nftBalance);
    }

    //When the dao organization makes an error in ruling on order issues, the administrator calls for compensation
    public entry fun compensate(sender: &signer, order : String) acquires CommerceInfo ,Orders{
        let commerce_info = borrow_global<CommerceInfo>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(commerce_info.admin == sender_addr,ERROR_NOT_ADMIN);

        let compensateCoin = dao::compensate(order);

        let orders = borrow_global<Orders>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<String,Order>(&orders.map, &order),ERROR_ORDER_NOT_EXISTS);
        let order = simple_map::borrow(&orders.map, &order);
        let business = order.orderBusiness;
        coin::deposit(business, compensateCoin);
    }

    //Dao Organization Initiates Order Adjudication Voting
    //Transfer pledged tokens back to the bankRoll contract.
    public entry fun refundVote(sender: &signer, order : String) acquires CommerceInfo , Orders{
        let refundAmount = dao::refund(sender, order);
        if(refundAmount > 0){
            refundByVote(order, refundAmount);
        }; 
    }

    //After the order is completed, the merchant withdraws funds
    public entry fun withdraw(orderId : String)acquires Orders, CommerceInfo, Shares, Profit, TaxationAvgs{
        
        let orders =  borrow_global_mut<Orders>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<String,Order>(&orders.map, &orderId),ERROR_ORDER_NOT_EXISTS);
        let order = simple_map::borrow_mut(&mut orders.map,&orderId);

        assert!(order.orderStatus,ERROR_HAVE_SELLED);
        assert!(order.orderPrice > 0,ERROR_CANNOT_WITHDRAW);
        let commerceInfo = borrow_global_mut<CommerceInfo>(RESOURCE_ACCOUNT);
        if(order.orderConfirm){
            assert!(order.orderData + commerceInfo.time <= timestamp::now_seconds(),ERROR_NOT_TIME_YET);
        }else if(order.orderDelay){
            assert!(order.orderData + 3 * commerceInfo.time <= timestamp::now_seconds(),ERROR_NOT_TIME_YET);
        }else{
            assert!(order.orderData + 2 * commerceInfo.time <= timestamp::now_seconds(),ERROR_NOT_TIME_YET);
        };

        let shares = borrow_global<Shares>(RESOURCE_ACCOUNT);
        let share = 0;
        if (simple_map::contains_key<address,simple_map::SimpleMap<String,u64>>(&shares.map, &order.orderBusiness)){
            let map1 = simple_map::borrow<address,simple_map::SimpleMap<String,u64>>(&shares.map, &order.orderBusiness);
            if(simple_map::contains_key<String,u64>(map1, &order.orderName)){
                share = *simple_map::borrow<String,u64>(map1, &order.orderName);
            };
        };
        
        let reward = order.orderPrice * share / 1000;
        if(order.orderPromoter2 == ZERO){
            if(order.orderPromoter1 == ZERO){
                reward = 0;
            }else{
                reward = reward * 80 / 100;
                let rewardCoin = coin::extract(&mut commerceInfo.balance_u, reward);
                coin::deposit(order.orderPromoter1, rewardCoin);
            }
            
        }else{
            let reward1 = reward * 80 / 100;
            let reward1Coin = coin::extract(&mut commerceInfo.balance_u, reward1);
            let reward2Coin = coin::extract(&mut commerceInfo.balance_u, reward - reward1);
            coin::deposit(order.orderPromoter1, reward1Coin);
            coin::deposit(order.orderPromoter2, reward2Coin);
        };
        
        let profits = borrow_global<Profit>(RESOURCE_ACCOUNT);
        let profit = 0;
        if (simple_map::contains_key<address,simple_map::SimpleMap<String,u64>>(&profits.map, &order.orderBusiness)){
            let map2 = simple_map::borrow<address,simple_map::SimpleMap<String,u64>>(&profits.map, &order.orderBusiness);
            if(simple_map::contains_key<String,u64>(map2, &order.orderName)){
                profit = *simple_map::borrow<String,u64>(map2,&order.orderName);
            };
        };
    
        let todao = order.orderPrice * (profit - share) /1000;
        let todaoCoin = coin::extract(&mut commerceInfo.balance_u, todao);
        dao::deposit_usdt(todaoCoin);

        //pay taxes
        let taxationAvgs = borrow_global<TaxationAvgs>(RESOURCE_ACCOUNT);
        let totaxation = 0;
        if(simple_map::contains_key<address,u64>(&taxationAvgs.map, &order.orderTaxation)){
            let avg =  *simple_map::borrow<address,u64>(&taxationAvgs.map, &order.orderTaxation);
            totaxation = order.orderPrice * avg / 1000;
            if(totaxation > 0){
                let totaxationCoin = coin::extract(&mut commerceInfo.balance_u, totaxation);
                coin::deposit(order.orderTaxation, totaxationCoin);
            };
        };
        

        let tobusiness = order.orderPrice - reward - todao - totaxation;
        let tobusinessCoin = coin::extract(&mut commerceInfo.balance_u, tobusiness);
        coin::deposit(order.orderBusiness,tobusinessCoin);

        order.orderStatus = false
    }
        
    //Buyers who purchase goods will receive corresponding NFT rewards.
    public entry fun pay(sender: &signer, orderIds :vector<String>,names :vector<String>,amountUsdts :vector<u64>,businesses :vector<address>,promoter1s:vector<address>,taxations:vector<address>) acquires CommerceInfo,Orders,Inviter,Shares{
        
        let orders = borrow_global_mut<Orders>(RESOURCE_ACCOUNT);
        let commerceInfo = borrow_global_mut<CommerceInfo>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);

        let leng = vector::length(&orderIds);
        let i = 0;
        while (i < leng) {
        
            let orderId = *vector::borrow<String>(&orderIds, i);
            let name = *vector::borrow<String>(&names, i);
            let amountUsdt = *vector::borrow<u64>(&amountUsdts, i);
            let business = *vector::borrow<address>(&businesses, i);
            let promoter1 = *vector::borrow<address>(&promoter1s, i);
            let taxation = *vector::borrow<address>(&taxations, i);
            i = i + 1;

            let coins = coin::withdraw<coins::USDT>(sender, amountUsdt);
            coin::merge(&mut commerceInfo.balance_u, coins);

            assert!(!simple_map::contains_key<String,Order>(&orders.map,&orderId), ERROR_ORDER_EXISTS);

            let inter :address;
            if(!exists<Inviter>(promoter1)){
                inter = ZERO;
            }else{
                inter = borrow_global<Inviter>(promoter1).inviter;
            };

            simple_map::add(&mut orders.map, orderId, Order{
                orderStatus: true,
                orderName: name,
                orderPrice: amountUsdt,
                orderData: timestamp::now_seconds(),
                orderDelay: false,
                orderBusiness: business,
                orderPromoter1: promoter1,
                orderPromoter2: inter,
                orderBuyer: sender_addr,
                orderTaxation: taxation,
                orderConfirm: false,
                orderNftId : 0,
            });

            let shares = borrow_global<Shares>(RESOURCE_ACCOUNT);

            //nft reward base share
            if(!simple_map::contains_key<address,simple_map::SimpleMap<String,u64>>(&shares.map, &business)) continue;

            let map1 = simple_map::borrow<address,simple_map::SimpleMap<String,u64>>(&shares.map, &business);
            if(!simple_map::contains_key<String,u64>(map1, &name)) continue;

            let realAmount = getTokenAmount(amountUsdt);
            if(realAmount == 0) continue;
            let share = *simple_map::borrow<String,u64>(map1, &name);
            let airdopAmount = realAmount * share / (1000 as u64);

            let airdopCoin = bankRoll::aridop(airdopAmount);
            let airdopCoinValue = coin::value(&airdopCoin);
            commerceNft::deposit_ct(airdopCoin);

            if(airdopCoinValue ==  airdopAmount){
                let nftId = commerceNft::pledge(orderId, airdopAmount, promoter1, inter, sender_addr);
                let order = simple_map::borrow_mut(&mut orders.map, &orderId);
                order.orderNftId = nftId;
            };
        
        };
       
    }

    fun getTokenAmount(amountUsdt:u64):u64{
        if(swap_utils::sort_token_type<coins::USDT, ct::CT>()){
            let (rin, rout, expA, expB,_) = swap::token_reserves<coins::USDT,ct::CT>();
            swap_utils::get_amount_out(amountUsdt, rin, rout,expA, expB)
        }else {
            let (rin, rout, expA, expB,_) = swap::token_reserves<ct::CT,coins::USDT>();
            swap_utils::get_amount_out(amountUsdt, rout, rin,expB, expA)
        }
    }


    fun refundByVote(orderId :String , amount : u64) acquires CommerceInfo , Orders{
        let commerce_info = borrow_global_mut<CommerceInfo>(RESOURCE_ACCOUNT);
        let orders = borrow_global_mut<Orders>(RESOURCE_ACCOUNT);

        assert!(simple_map::contains_key<String,Order>(&orders.map, &orderId),ERROR_ORDER_NOT_EXISTS);
        let order = simple_map::borrow_mut<String,Order>(&mut orders.map, &orderId);

        assert!(order.orderPrice >= amount,ERROR_NO_ENOUGH_BALANCE);
        let refundCoin = coin::extract(&mut commerce_info.balance_u, amount);
        coin::deposit(order.orderBuyer,refundCoin);

        let amount1 = order.orderPrice;
        order.orderPrice = order.orderPrice - amount;
        if(amount1 == amount){
            order.orderStatus = false;
        };

        let nftId = order.orderNftId;
        let backCoin = commerceNft::unpledgeSome(nftId, amount, amount1);
        bankRoll::deposit_ct(backCoin);
    }

    //Merchant Refund
    //Transfer pledged tokens back to the bankRoll contract.
    public entry fun refund(sender: &signer, orderId :String , amount : u64) acquires CommerceInfo , Orders{
        let commerce_info = borrow_global_mut<CommerceInfo>(RESOURCE_ACCOUNT);
        let orders = borrow_global_mut<Orders>(RESOURCE_ACCOUNT);
        let order = simple_map::borrow_mut<String,Order>(&mut orders.map, &orderId);

        let sender_addr = signer::address_of(sender);
        assert!(order.orderBusiness == sender_addr,ERROR_NOT_ALLOW);
        assert!(order.orderPrice >= amount,ERROR_NO_ENOUGH_BALANCE);
        let refundCoin = coin::extract(&mut commerce_info.balance_u, amount);
        coin::deposit(order.orderBuyer,refundCoin);

        let amount1 = order.orderPrice;
        order.orderPrice = order.orderPrice - amount;
        if(amount1 == amount){
            order.orderStatus = false;
        };

        let nftId = order.orderNftId;
        let backCoin = commerceNft::unpledgeSome(nftId,amount,amount1);
        bankRoll::deposit_ct(backCoin);
    }

    //After the order is completed, the buyer can sell the NFT
    public entry fun sellNft(sender :&signer, nftId : u128) acquires Orders{
        let orderId = commerceNft::getOrderId(nftId);
        let orders = borrow_global<Orders>(RESOURCE_ACCOUNT);
        let order = simple_map::borrow(&orders.map, &orderId);
        assert!(order.orderStatus == false, ERROR_NOT_ALLOW);
        commerceNft::sellNft(sender, nftId);

    }

    //Store owners can call this function to bind recommenders
    public entry fun openShop(sender: &signer, inter: address){
        let sender_addr = signer::address_of(sender);
        assert!(!exists<Inviter>(sender_addr), ERROR_HAVE_INVITER);
        
        move_to(sender,Inviter{
            inviter : inter,
        });
    }

    //Buyer confirms receipt
    public entry fun confirm(sender : &signer, orderId :String) acquires Orders{
        let sender_addr = signer::address_of(sender);
        let orders =  borrow_global_mut<Orders>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<String,Order>(&orders.map, &orderId), ERROR_ORDER_NOT_EXISTS);

        let order = simple_map::borrow_mut<String,Order>(&mut orders.map, &orderId);
        assert!(order.orderBuyer == sender_addr, ERROR_NOT_BUYER);
        assert!(order.orderConfirm == false, ERROR_HAVE_CONFIRM);
        order.orderData = timestamp::now_seconds();
        order.orderConfirm = true
    }

    //Buyer delay
    public entry fun delay(sender: &signer,orderId: string::String) acquires Orders{
        let sender_addr = signer::address_of(sender);
        let orders =  borrow_global_mut<Orders>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<String,Order>(&orders.map, &orderId), ERROR_ORDER_NOT_EXISTS);

        let order = simple_map::borrow_mut<String,Order>(&mut orders.map, &orderId);
        assert!(order.orderBuyer == sender_addr,ERROR_NOT_BUYER);
        assert!(order.orderDelay == false,ERROR_HAVED_DELAY);
        order.orderDelay = true;
    }

    //Merchant Opening Pledge
    public entry fun pledge(sender: &signer, amount: u64) acquires CommerceInfo, Pledges{
        let amountCoin = coin::withdraw<coins::USDT>(sender, amount);
        let commerce_info = borrow_global_mut<CommerceInfo>(RESOURCE_ACCOUNT);
        coin::merge(&mut commerce_info.balance_u, amountCoin);
        
        let pledges = borrow_global_mut<Pledges>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        if(simple_map::contains_key<address,u64>(&pledges.map, &sender_addr)){
            let pledge =  *simple_map::borrow<address,u64>(&pledges.map, &sender_addr);
            *simple_map::borrow_mut<address,u64>(&mut pledges.map, &sender_addr) = pledge + amount;
    
        }else{
            simple_map::add(&mut pledges.map, sender_addr, amount)
        };
    }

    //Merchant's Release of Pledge
    public entry fun unpledge(sender :&signer, business : address, amount : u64) acquires CommerceInfo, Pledges{
        let commerceInfo = borrow_global_mut<CommerceInfo>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(commerceInfo.admin == sender_addr,ERROR_NOT_ADMIN);

        let pledges = borrow_global_mut<Pledges>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<address,u64>(&pledges.map, &business), ERROR_NO_PLEDGE);

        let pledge = *simple_map::borrow<address,u64>(&pledges.map, &business);
        assert!(pledge >= amount, ERROR_NO_ENOUGH_BALANCE);
        *simple_map::borrow_mut<address,u64>(&mut pledges.map, &business) = pledge - amount;

        let unpledgeCoin = coin::extract(&mut commerceInfo.balance_u, amount);
        coin::deposit(business, unpledgeCoin);
    }

    //Administrators set parameters for merchant products
    public entry fun setBusinessProfitAndShares(sender: &signer, business: address, name: String, profit_outer: u64, shares_outer: u64)acquires CommerceInfo,Shares,Profit{
        assert!(profit_outer * 15 / 100 >= shares_outer, ERROR_SHARES_TOOBIG);
        let commerceInfo = borrow_global<CommerceInfo>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(commerceInfo.admin == sender_addr, ERROR_NOT_ADMIN);

        let shares = borrow_global_mut<Shares>(RESOURCE_ACCOUNT);
        let profit = borrow_global_mut<Profit>(RESOURCE_ACCOUNT);
        
        if(simple_map::contains_key<address,simple_map::SimpleMap<String,u64>>(&shares.map, &business)){
            let map1 = simple_map::borrow_mut<address,simple_map::SimpleMap<String,u64>>(&mut shares.map, &business);
            if(simple_map::contains_key<String,u64>(map1, &name)){
                *simple_map::borrow_mut<String,u64>(map1, &name) = shares_outer;
            }else{
                simple_map::add(map1, name, shares_outer);
            }
        }else{
           let sm = simple_map::create<String,u64>();
           simple_map::add(&mut shares.map, business, sm); 
           let map1 = simple_map::borrow_mut<address,simple_map::SimpleMap<String,u64>>(&mut shares.map, &business);
           simple_map::add(map1, name, shares_outer);

        }; 

        if(simple_map::contains_key<address,simple_map::SimpleMap<String,u64>>(&profit.map, &business)){
            let map1 = simple_map::borrow_mut<address,simple_map::SimpleMap<String,u64>>(&mut profit.map, &business);
            if(simple_map::contains_key<String,u64>(map1, &name)){
                *simple_map::borrow_mut<String,u64>(map1, &name) = profit_outer;
            }else{
                simple_map::add(map1, name, profit_outer);
            }
        }else{
           let sm = simple_map::create<String,u64>();
           simple_map::add(&mut profit.map, business, sm); 
           let map1 = simple_map::borrow_mut<address,simple_map::SimpleMap<String,u64>>(&mut profit.map, &business);
           simple_map::add(map1, name, profit_outer);

        }; 

    }

    //Administrator sets tax parameters
    public entry fun setTaxation(sender :&signer, taxation : address , avg : u64) acquires CommerceInfo,TaxationAvgs{
        let commerceInfo = borrow_global<CommerceInfo>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(commerceInfo.admin == sender_addr, ERROR_NOT_ADMIN);

        let taxationAvgs = borrow_global_mut<TaxationAvgs>(RESOURCE_ACCOUNT);
        if(simple_map::contains_key<address,u64>(&taxationAvgs.map, &taxation)){
            *simple_map::borrow_mut<address,u64>(&mut taxationAvgs.map, &taxation) = avg;
        }else{
            simple_map::add(&mut taxationAvgs.map, taxation, avg);
        };
    }

    //Administrator sets the product settlement cycle
    public entry fun setTime(sender :&signer, time_out : u64) acquires CommerceInfo{
        let commerceInfo = borrow_global_mut<CommerceInfo>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(commerceInfo.admin == sender_addr, ERROR_NOT_ADMIN);

        commerceInfo.time = time_out * 24 * 60 * 60;
    }

    public entry fun setTestTime(sender :&signer, time_out : u64) acquires CommerceInfo{
        let commerceInfo = borrow_global_mut<CommerceInfo>(RESOURCE_ACCOUNT);
        let sender_addr = signer::address_of(sender);
        assert!(commerceInfo.admin == sender_addr, ERROR_NOT_ADMIN);

        commerceInfo.time = time_out;
    }

    #[view]
    public fun getOrderInfo(orderId: String) : Order acquires Orders{
        let orders = borrow_global<Orders>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<String,Order>(&orders.map, &orderId), ERROR_ORDER_NOT_EXISTS);
        
        let order = simple_map::borrow<String,Order>(&orders.map, &orderId);
        *order
    }

}
