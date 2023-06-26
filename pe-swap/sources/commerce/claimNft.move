module nft_resource_account::token {
    use equity::commerceNft;

    use std::signer; 
    use std::string::{Self, String}; 
    use std::bcs;
    use aptos_token::token;
    use aptos_token::token::TokenDataId;
    use aptos_framework::account;
    use aptos_framework::resource_account;

    const RESOURCE_ACCOUNT: address = @nft_resource_account;
    const DEV: address = @nft_account;

    struct NftInfo has key {
        signer_cap: account::SignerCapability,
    }

    // This struct stores an NFT collection's relevant information
    struct ModuleData has key {
        token_data_id: TokenDataId,
    }

    fun init_module(sender: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(sender, DEV);
        move_to(sender, NftInfo {
            signer_cap,
        });

        let collection_name = string::utf8(b"Commerce collection Nft");
        let description = string::utf8(b"nft for commerce");
        let collection_uri = string::utf8(b"Collection uri");
        let token_name = string::utf8(b"Commerce Nft");
        let token_uri = string::utf8(b"Token uri");
        // This means that the supply of the token will not be tracked.
        let maximum_supply = 0;
        // This variable sets if we want to allow mutation for collection description, uri, and maximum.
        // Here, we are setting all of them to false, which means that we don't allow mutations to any CollectionData fields.
        let mutate_setting = vector<bool>[ false, false, false ];

        // Create the nft collection.
        token::create_collection(sender, collection_name, description, collection_uri, maximum_supply, mutate_setting);

        // Create a token data id to specify the token to be minted.
        let token_data_id = token::create_tokendata(
            sender,
            collection_name,
            token_name,
            string::utf8(b""),
            0,
            token_uri,
            signer::address_of(sender),
            1,
            0,
            // This variable sets if we want to allow mutation for token maximum, uri, royalty, description, and properties.
            // Here we enable mutation for properties by setting the last boolean in the vector to true.
            token::create_token_mutability_config(
                &vector<bool>[ false, false, false, false, true ]
            ),
            // We can use property maps to record attributes related to the token.
            // In this example, we are using it to record the receiver's address.
            // We will mutate this field to record the user's address
            // when a user successfully mints a token in the `mint_nft()` function.
            vector<String>[string::utf8(b"given_to")],
            vector<vector<u8>>[b""],
            vector<String>[ string::utf8(b"address") ],
        );

        // Store the token data id within the module, so we can refer to it later
        // when we're minting the NFT and updating its property version.
        move_to(sender, ModuleData {
            token_data_id,
        });
    }

    public entry fun claimNft(receiver: &signer,nftId: u128) acquires ModuleData , NftInfo{
        
        commerceNft::canClaim(receiver , nftId);
        
        let nft_info = borrow_global<NftInfo>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&nft_info.signer_cap);
        // Mint token to the resource_signer.
        let module_data = borrow_global_mut<ModuleData>(RESOURCE_ACCOUNT);
        let token_id = token::mint_token(&resource_signer, module_data.token_data_id, 1);

        //transfer token to the receiver.
        token::direct_transfer(&resource_signer, receiver, token_id, 1);

        // Mutate the token properties to update the property version of this token.
        // Note that here we are re-using the same token data id and only updating the property version.
        // This is because we are simply printing edition of the same token, instead of creating
        // tokens with unique names and token uris. The tokens created this way will have the same token data id,
        // but different property versions.
        let (creator_address, collection, name) = token::get_token_data_id_fields(&module_data.token_data_id);
        token::mutate_token_properties(
            &resource_signer,
            signer::address_of(receiver),
            creator_address,
            collection,
            name,
            0,
            1,
            // Mutate the properties to record the receiveer's address.
            vector<String>[string::utf8(b"given_to")],
            vector<vector<u8>>[bcs::to_bytes(&signer::address_of(receiver))],
            vector<String>[ string::utf8(b"address") ],
        );
    }


}