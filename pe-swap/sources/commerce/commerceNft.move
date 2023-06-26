module equity::commerceNft {
    use equity::ct;
    use equity::dao;
    use equity::coins;
    use equity::swap;
    use equity::swap_utils;
    use std::signer; 
    use std::string::{Self, String}; 
    use aptos_std::simple_map;
    use aptos_framework::coin;
    

    friend equity::commerce;

    const RESOURCE_ACCOUNT: address = @equity;
    const ZERO : address = @zero;

    const ERROR_NOT_ALLOW: u64 = 0;
    const ERROR_NFTID_NOT_EXISTS: u64 = 1;
    const ERROR_NFT_PLEDGE: u64 = 2;

    struct CommerceNftInfo has key {
        balance_ct: coin::Coin<ct::CT>,
        nft_total : u128,
    }

    struct NftInfo has copy, drop, store {
        canMint: bool,
        nftName: String,
        nftPledge: bool,
        nftPrice: u64,
        nftPromoter1: address,
        nftPromoter2: address,
        nftOwner: address,
    }

    struct NftInfos has key{
         map : simple_map::SimpleMap<u128, NftInfo>,
    }

    fun init_module(sender: &signer) {

        move_to(sender, CommerceNftInfo {
            balance_ct: coin::zero<ct::CT>(),
            nft_total: (0 as u128),
        });

        move_to(sender, NftInfos{
            map : simple_map::create<u128, NftInfo>(),
        });

    }

    //NFT Rewards
    public (friend) fun pledge(order : string::String, amount :u64, promoter1 : address, promoter2 : address,  to :address):u128 acquires CommerceNftInfo,NftInfos{
        let commerceNft_info = borrow_global_mut<CommerceNftInfo>(RESOURCE_ACCOUNT);
        let nft_infos = borrow_global_mut<NftInfos>(RESOURCE_ACCOUNT);

        commerceNft_info.nft_total = commerceNft_info.nft_total + 1;
        let nftId = commerceNft_info.nft_total;
        
        simple_map::add(&mut nft_infos.map, nftId, NftInfo{
            canMint: false,
            nftName: order,
            nftPledge: true,
            nftPrice: amount,
            nftPromoter1: promoter1,
            nftPromoter2: promoter2,
            nftOwner: to,

            });
        nftId
        
    }

    //When the order is fully or partially refunded, update the corresponding NFT reward.
    public (friend) fun unpledgeSome(nftId : u128,amount:u64, amount1:u64) : coin::Coin<ct::CT>  acquires CommerceNftInfo,NftInfos{
        let commerceNft_info = borrow_global_mut<CommerceNftInfo>(RESOURCE_ACCOUNT);
        
        let nft_infos = borrow_global_mut<NftInfos>(RESOURCE_ACCOUNT);
        let nft_info = simple_map::borrow_mut(&mut nft_infos.map, &nftId);
        assert!(nft_info.nftPledge, ERROR_NOT_ALLOW);
        let am = nft_info.nftPrice * amount / amount1;
        let backCoin = coin::extract(&mut commerceNft_info.balance_ct, am);
        if(amount1 == amount){

            nft_info.nftName = string::utf8(b"");
            nft_info.nftPledge = false;
            nft_info.nftPrice = 0;
            nft_info.nftPromoter1 = ZERO;
            nft_info.nftPromoter2 = ZERO;
            nft_info.nftOwner = ZERO;
        }else{
            
            nft_info.nftPrice = nft_info.nftPrice - am;
            
        };
        backCoin
    }

    //Sell tokens and distribute dividends to recommenders
    public (friend) fun sellNft(sender :&signer, nftId : u128) acquires NftInfos ,CommerceNftInfo{
        let nft_infos = borrow_global_mut<NftInfos>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<u128,NftInfo>(&nft_infos.map, &nftId), ERROR_NFTID_NOT_EXISTS);

        let nft_info = simple_map::borrow_mut<u128,NftInfo>(&mut nft_infos.map, &nftId);
        let sender_addr = signer::address_of(sender);
        assert!(nft_info.nftOwner == sender_addr, ERROR_NOT_ALLOW);

        assert!(nft_info.nftPledge, ERROR_NOT_ALLOW);
        nft_info.nftPledge = false;
        nft_info.canMint = true;
        
        let commerceNft_info = borrow_global_mut<CommerceNftInfo>(RESOURCE_ACCOUNT);
        let swapCoin = coin::extract(&mut commerceNft_info.balance_ct, nft_info.nftPrice);

        let t1 = nft_info.nftPromoter1;
        let t2 = nft_info.nftPromoter2;
        if (swap_utils::sort_token_type<ct::CT, coins::USDT>()) {
            let (coins_x_out, coins_y_out) = swap::swap_exact_x_to_y_direct<ct::CT, coins::USDT>(swapCoin);
            coin::destroy_zero(coins_x_out);
            let amount_out = coin::value(&coins_y_out);
            if(t1 != ZERO){
                let reward1 = amount_out * 16 /100;
                let reward1Coin = coin::extract(&mut coins_y_out, reward1);
                coin::deposit(t1, reward1Coin);
            };
            if(t2 != ZERO){
                let reward2 = amount_out * 4 /100;
                let reward2Coin = coin::extract(&mut coins_y_out, reward2);
                coin::deposit(t2,reward2Coin);
            }else{
                let reward2 = amount_out * 4 /100;
                let reward2Coin = coin::extract(&mut coins_y_out, reward2);
                dao::deposit_usdt(reward2Coin);
            };
            coin::deposit(nft_info.nftOwner,coins_y_out);

        } else {
            let (coins_x_out, coins_y_out) = swap::swap_exact_y_to_x_direct<coins::USDT, ct::CT>(swapCoin);
            coin::destroy_zero(coins_y_out);
            let amount_out = coin::value(&coins_x_out);
            if(t1 != ZERO){
                let reward1 = amount_out * 16 /100;
                let reward1Coin = coin::extract(&mut coins_x_out, reward1);
                coin::deposit(t1, reward1Coin);
            };
            if(t2 != ZERO){
                let reward2 = amount_out * 4 /100;
                let reward2Coin = coin::extract(&mut coins_x_out, reward2);
                coin::deposit(t2, reward2Coin);
            }else{
                let reward2 = amount_out * 4 /100;
                let reward2Coin = coin::extract(&mut coins_x_out, reward2);
                dao::deposit_usdt(reward2Coin);
            };
            coin::deposit(nft_info.nftOwner,coins_x_out);
        };
        
    }

    //Casting nft calls, do not directly call
    public fun canClaim(receiver : &signer, nftId : u128) acquires NftInfos{
        let nft_infos = borrow_global_mut<NftInfos>(RESOURCE_ACCOUNT);
        assert!(simple_map::contains_key<u128, NftInfo>(&nft_infos.map, &nftId),ERROR_NFTID_NOT_EXISTS);
        let nft_info = simple_map::borrow_mut<u128, NftInfo>(&mut nft_infos.map, &nftId);
        assert!(nft_info.canMint, ERROR_NOT_ALLOW);
        nft_info.canMint = false;
        assert!(nft_info.nftPledge == false, ERROR_NFT_PLEDGE);
        let to = signer::address_of(receiver);
        assert!(nft_info.nftOwner == to, ERROR_NOT_ALLOW);
    }

    #[view]
    public fun getOrderId(nftId : u128) : String acquires NftInfos{
        let nft_infos = borrow_global<NftInfos>(RESOURCE_ACCOUNT);
        let nft_info = simple_map::borrow(&nft_infos.map, &nftId);
        nft_info.nftName
    }

    #[view]
    public fun getNftInfo(nftId : u128) : NftInfo acquires NftInfos{
        let nft_infos = borrow_global<NftInfos>(RESOURCE_ACCOUNT);
        let nft_info = simple_map::borrow<u128,NftInfo>(&nft_infos.map, &nftId);
        *nft_info
    }

    #[view]
    public fun getAddressTokenBalance(addr : address) : u64 acquires CommerceNftInfo , NftInfos{
        let commerceNft_info = borrow_global<CommerceNftInfo>(RESOURCE_ACCOUNT);
        let nft_infos = borrow_global<NftInfos>(RESOURCE_ACCOUNT);
        let len = commerceNft_info.nft_total;
        let i = 1;
        let balance = 0;
        while (i <= len) {
            let nft_info = simple_map::borrow(&nft_infos.map , &i);
            if(nft_info.nftPledge && nft_info.nftOwner == addr){
                balance = balance + nft_info.nftPrice;
            };
            i = i + 1;
        } ;
        balance
    }

    public (friend) fun deposit_ct(amount: coin::Coin<ct::CT>):bool acquires CommerceNftInfo{
        let commerceNft_info = borrow_global_mut<CommerceNftInfo>(RESOURCE_ACCOUNT);
        
        coin::merge(&mut commerceNft_info.balance_ct,amount);
        true
        
    }
}