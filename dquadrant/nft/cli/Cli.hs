{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
{-# OPTIONS_GHC -Wno-incomplete-patterns #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

module Cli (
readTip
)
where

import qualified Plutus.V1.Ledger.Api as Plutus
import qualified Data.ByteString.Short as SBS
import qualified Cardano.Ledger.Alonzo.Data as Alonzo
import System.Environment (getArgs, getEnv)
import qualified Data.ByteString.Char8 as C
import Data.Text.Encoding ( decodeUtf8, encodeUtf8 )
import qualified Data.ByteString.Lazy as LBS
import Plutus.Contract.Blockchain.MarketPlace (marketValidator, Market (..), DirectSale (DirectSale, dsAsset, dsSeller), SellType (Primary), marketAddress, MarketRedeemer (Buy), dsFee, dsPaymentValueList)
-- import           Cardano.Api.Byron hiding (SomeByronSigningKey (..))
import Cardano.Api
import qualified Cardano.Api.Shelley
import Cardano.Api.Shelley (fromPlutusData, Lovelace (Lovelace), Tx (ShelleyTx), PlutusScript (PlutusScriptSerialised), toAlonzoData, ProtocolParameters (protocolParamTxFeeFixed), TxBody (ShelleyTxBody))

import Cardano.CLI.Shelley.Script


import Ledger (pubKeyHash, datumHash, Datum (Datum), Tx, txId, PubKeyHash (PubKeyHash))
import Data.Text.Conversions (Base16(Base16, unBase16), ToText (toText), FromText (fromText), UTF8 (unUTF8, UTF8), Base64, DecodeText (decodeText), convertText)
import Data.ByteString(ByteString(), split, unpack)
import Data.Text (Text)
import Data.Functor ((<&>))
import System.Posix.Types
import Plutus.V1.Ledger.Api
    ( toBuiltin,
      BuiltinByteString,
      builtinDataToData,
      fromBuiltin,
      toData,
      FromData,
      CurrencySymbol(CurrencySymbol),
      TokenName(TokenName), ToData (toBuiltinData), BuiltinData (BuiltinData) )
import Plutus.V1.Ledger.Value (assetClass, tokenName, AssetClass (AssetClass))
import qualified Data.Text as T
import Text.Read (readMaybe, Lexeme (Number))
import Cardano.CLI.Types (SocketPath(SocketPath), TxOutChangeAddress (TxOutChangeAddress))
import PlutusTx.Builtins (sha2_256, sha3_256)
import Data.ByteString.Lazy (toStrict, fromStrict)
import Data.Aeson (ToJSON(toJSON), encode, decode)
import Codec.Serialise (serialise, deserialise)
import Plutus.V1.Ledger.Address (Address(Address))
import qualified Data.Set as Set
import qualified Data.Map as Map
import qualified Data.Map.Strict as StrictMap
import qualified Data.Sequence.Strict as Seq

import Control.Monad (unless, void)
import System.Posix.Internals (withFilePath)
import Cardano.Api.NetworkId.Extra (testnetNetworkId)
import Control.Exception (try, handle, handleJust, throw)
import Cardano.Ledger.Alonzo.Tx (ValidatedTx(ValidatedTx))
import qualified Cardano.Ledger.Alonzo.TxBody as Alonzo
import qualified Cardano.Ledger.ShelleyMA.AuxiliaryData as Allegra
import qualified Cardano.Ledger.ShelleyMA.AuxiliaryData as Mary
import qualified Cardano.Ledger.ShelleyMA.TxBody as Allegra
import qualified Cardano.Ledger.ShelleyMA.TxBody as Mary
import Cardano.Ledger.ShelleyMA.TxBody (ValidityInterval(ValidityInterval, invalidBefore, invalidHereafter))

import qualified Shelley.Spec.Ledger.Genesis as Shelley
import qualified Shelley.Spec.Ledger.Metadata as Shelley
import qualified Shelley.Spec.Ledger.Tx as Shelley
import qualified Shelley.Spec.Ledger.TxBody as Shelley
import qualified Shelley.Spec.Ledger.UTxO as Shelley

import qualified Ouroboros.Network.Protocol.LocalStateQuery.Client as Net.Query
import           Ouroboros.Network.Protocol.LocalStateQuery.Type (AcquireFailure (..))
import qualified Ouroboros.Network.Protocol.LocalStateQuery.Type as Net.Query
import qualified Ouroboros.Network.Protocol.LocalTxSubmission.Client as Net.Tx
import Ouroboros.Network.Protocol.LocalTxSubmission.Type
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import GHC.Exception.Type (Exception)
import Cardano.CLI.Run (renderClientCommandError, runClientCommand, ClientCommand (ShelleyCommand))
import Control.Monad.Trans.Except.Exit (orDie)
import Data.Maybe (mapMaybe)
import Data.Set (toList)
import Cardano.CLI.Shelley.Key (deserialiseInputAnyOf)
import Data.Text.Prettyprint.Doc (Pretty(pretty))
import Ouroboros.Network.AnchoredFragment (prettyPrint)
import System.FilePath (joinPath)
import qualified Data.ByteString as BS
import System.Directory
import GHC.IO.Exception (IOException(IOError))
import qualified Ledger.AddressMap
import           Data.Map.Strict (Map)
import Data.String (IsString)
import GHC.Exts (IsString(fromString))
import Shelley.Spec.Ledger.API (Credential(ScriptHashObj, KeyHashObj))
import PlutusTx.IsData (FromData(fromBuiltinData))
import qualified Cardano.Ledger.Mary.Value (Value(Value))
import qualified Cardano.Ledger.Alonzo.TxBody as LedgerBody
import Control.Monad.Trans.Reader
  ( Reader,
    ReaderT,
    ask,
    reader,
    runReader,
  )
import Control.Monad.IO.Class (MonadIO (liftIO))
import           Data.Aeson.Encode.Pretty (encodePretty)
import Error
import TxUtils
import Nft


unHex ::  ToText a => a -> Maybe  ByteString
unHex v = convertText (toText v) <&> unBase16

unHexBs :: ByteString -> Maybe ByteString
unHexBs v =  decodeText (UTF8 v) >>= convertText  <&> unBase16

toHexString :: (FromText a1, ToText (Base16 a2)) => a2 -> a1
toHexString bs = fromText $  toText (Base16 bs )

-- unHex :: String -> ByteString
-- unHex input =toText test
--   where
--     hexText= t  input

unMaybe :: Applicative f =>  SomeError -> Maybe a  -> f a
unMaybe  e m= case m of
  Just v -> pure v
  Nothing -> throw  e

unEither :: Applicative f =>   Either SomeError a  -> f a
unEither e=case e of
    Left v -> throw v
    Right r -> pure r

maybeToEither ::  SomeError ->Maybe  a-> Either SomeError a
maybeToEither e m = case m of
  Nothing -> Left e
  Just a -> Right a

defaultMarket :: Market
defaultMarket = Market{
  mOperator   = Plutus.PubKeyHash  "1b5486c2b84712b4efa13e4bc2478bac76cb4d1569addfb9117cef39",
  mAuctionFee =1_000_000 ,  -- 5%
  mPrimarySaleFee =5_000_000, -- 5%
  mSecondarySaleFee=2_500_000 -- 2.5%
}

getConnection :: IO (LocalNodeConnectInfo CardanoMode)
getConnection = do
  sockEnv <- try $ getEnv "CARDANO_NODE_SOCKET_PATH"
  socketPath <-case  sockEnv of
    Left (e::IOError) -> do
          defaultSockPath<- getWorkPath ["testnet","node.socket"]
          exists<-doesFileExist defaultSockPath
          if exists then return defaultSockPath else throw (SomeError $ "Socket File is Missing: "++defaultSockPath ++"\n\tSet environment variable CARDANO_NODE_SOCKET_PATH  to use different path")
    Right s -> pure s
  pure (localNodeConnInfo socketPath)

readTip :: ReaderT () IO String
readTip = do
  liftIO getTip


getTip :: IO String
getTip = do
  conn <- getConnection
  tip <- getLocalChainTip conn
  pure (C.unpack . LBS.toStrict $ encodePretty tip)


main :: IO ()
main = do
  args <- getArgs
  sockEnv <- try $ getEnv "CARDANO_NODE_SOCKET_PATH"
  socketPath <-case  sockEnv of
    Left (e::IOError) -> do
          defaultSockPath<- getWorkPath ["testnet","node.socket"]
          exists<-doesFileExist defaultSockPath
          if exists then return defaultSockPath else throw (SomeError $ "Socket File is Missing: "++defaultSockPath ++"\n\tSet environment variable CARDANO_NODE_SOCKET_PATH  to use different path")
    Right s -> pure s
  let nargs = length args
  let scriptname = "marketplace.plutus"
  let conn= localNodeConnInfo socketPath

  case nargs of
    0 -> printHelp
    _ ->
      case  head args of
        "sell"-> if length args /= 3 then putStrLn  "Usage \n\tmarket-cli datum sell SellerPubKeyHash CurrencySymbol:TokenName CostInAda" else placeOnMarket conn $ tail args
        "buy"-> if length args /= 3 then putStrLn  "Usage \n\tmarket-cli  buy txHash#UtxoIndex datumHex" else buyToken defaultMarket conn $ tail args
        "compile" -> do
          writePlutusScript 42 scriptname (marketScriptPlutus defaultMarket) (marketScriptBS defaultMarket)
          putStrLn $ "Script Written to : " ++ scriptname
          putStrLn $ "Market  :: " ++ ( show $ marketAddress defaultMarket )
        "compile-nft-script" -> do
          writePlutusScript 42 "nft.plutus" nftMintingScript mintingNFTScriptShortBs
        
        "balance" -> runBalanceCommand  conn (map toText $ tail args)
        "connect" -> runConnectionTest conn
        "keygen"  -> runGenerateKey
        "import"  -> runImportKey $ tail args
        "pay" -> runPayCommand conn (tail args)
        "mint" -> runMintNft conn (tail args)

        _ -> printHelp

  where
    printHelp =do
      args <- getArgs
      putStrLn $ "Unknown options " ++show args


runMintNft conn [nameStr] = do 

        paramQueryResult<-queryNodeLocalState conn Nothing protocolParamsQuery
        pParam<-case paramQueryResult of
          Left af -> throw $ SomeError  "Acquire Failure"
          Right e -> case e of
            Left em -> throw $ SomeError "Missmatched Era"
            Right pp -> return pp

        sKey <-getDefaultSignKey
        let walletAddr = toAddressAny $ skeyToAddr sKey
        alonzoWalletAddr<-unMaybe "Address not supported in alonzo era" $ anyAddressInEra AlonzoEra walletAddr

        utxos <-queryUtxoList  conn  walletAddr

        let inputs = map utxosWithWitness utxos
            values = map utxosValue utxos
            totalInputValue = sumValue values

        scriptPath <- getWorkPath ["nft.plutus"]
        scriptWitness <- createScriptWitness' AlonzoEra scriptPath


        let policyId = scriptWitnessPolicyId' scriptWitness
            witnessProvidedMap = StrictMap.fromList [(policyId, scriptWitness)] 
            buildTx = BuildTxWith witnessProvidedMap
            nftValue = valueFromList [
                                  (AssetId policyId getAssetName, Quantity 1)
                                ]
            totalOutputValue = totalInputValue <> nftValue
            txOuts = composeTxOuts alonzoWalletAddr totalOutputValue
            txMintValue = TxMintValue MultiAssetInAlonzoEra nftValue buildTx

            bodyContent = makeTxBodyContent inputs txOuts pParam 0 txMintValue
                -- (TxBodyContent {
                --   txIns= inputs,
                --   txInsCollateral=TxInsCollateral CollateralInAlonzoEra  [  ],
                --   txOuts= composeTxOuts alonzoWalletAddr txOutValue
                --   txFee=TxFeeExplicit TxFeesExplicitInAlonzoEra $ Lovelace 0,
                --   txValidityRange=(TxValidityNoLowerBound,TxValidityNoUpperBound ValidityNoUpperBoundInAlonzoEra),
                --   txMetadata=TxMetadataNone ,
                --   txAuxScripts=TxAuxScriptsNone,
                --   txExtraScriptData=BuildTxWith TxExtraScriptDataNone ,
                --   txExtraKeyWits=TxExtraKeyWitnessesNone,
                --   txProtocolParams=BuildTxWith (Just  pParam),
                --   txWithdrawals=TxWithdrawalsNone,
                --   txCertificates=TxCertificatesNone,
                --   txUpdateProposal=TxUpdateProposalNone,
                --   txMintValue=TxMintValue MultiAssetInAlonzoEra nftValue buildTx,
                --   txScriptValidity=TxScriptValidityNone
                -- })

        case makeTransactionBody bodyContent of
          Left tbe ->
            throw $ SomeError "Tx Body has error."
          Right txBody -> do
            let Lovelace transactionFee = evaluateTransactionFee pParam txBody 1 0
                newwalletValue = totalOutputValue <> (negateValue (lovelaceToValue $ Lovelace transactionFee))
                                    <> (negateValue (lovelaceToValue $ Lovelace 176))

                newTxOuts = composeTxOuts alonzoWalletAddr newwalletValue
                newBodyContent = makeTxBodyContent inputs newTxOuts pParam (transactionFee+176) txMintValue
            case makeTransactionBody newBodyContent of
              Left tbe -> throw $ SomeError "Tx Body has error."
              Right newTxBody -> do
                signAndSubmitTransaction conn sKey newTxBody




    where
      protocolParamsQuery= QueryInEra AlonzoEraInCardanoMode
                    $ QueryInShelleyBasedEra ShelleyBasedEraAlonzo QueryProtocolParameters
    
      utxosWithWitness (txin,txout) = (txin, BuildTxWith $ KeyWitness KeyWitnessForSpending)

      sumValue [] = lovelaceToValue $ Lovelace 0
      sumValue (x:xs) = x <> sumValue xs

      composeTxOuts alonzoWalletAddr walletValue = [
                TxOut alonzoWalletAddr (TxOutValue MultiAssetInAlonzoEra walletValue) TxOutDatumHashNone
        ]
      utxosValue (txin, TxOut _ (TxOutValue _ value) _) = value

      -- policyHex = "aa3f638ea4a9572a46b36eb69ceb3ee7051996b7b7e960f0de1938c8"
      -- getPolicyId = case textToPolicyId policyHex of
      --   Just p -> p
      --   Nothing -> throw $ SomeError "Failed to parse policy id."


      -- textToPolicyId =
      --     fmap PolicyId
      --   . deserialiseFromRawBytesHex AsScriptHash
      --   . Text.encodeUtf8
      --   . Text.pack

      getAssetName = AssetName $ Text.encodeUtf8 $ Text.pack nameStr



createScriptWitness'
  :: CardanoEra era
  -> FilePath
  -> IO (ScriptWitness WitCtxMint era)
createScriptWitness' era scriptPath = do
  --TODO
  let requiredMemory = 700000000
      requiredSteps  = 700000000

  eitherPolicyFile <- try readScriptFromFile
  case eitherPolicyFile of
    Left (e::IOError )-> throw $ SomeError "There was error reading policy file"
    Right scriptAnyLang -> do
      ScriptInEra langInEra script'   <- validateScriptSupportedInEra' era scriptAnyLang
      case script' of
        PlutusScript version sscript ->
          return $ PlutusScriptWitness
                    langInEra version sscript
                    NoScriptDatumForMint
                    (ScriptDataNumber 1)
                    (ExecutionUnits requiredSteps requiredMemory)

        SimpleScript{} -> throw $ SomeError  "Error this is a plutus script not simple script."

  where
    readScriptFromFile = do
      exists <- doesFileExist scriptPath
      if exists then pure () else throw (SomeError $ scriptPath ++ "  doesn't exist")
      scriptBytes <- BS.readFile scriptPath
      let scriptInAnyLang = deserialiseScriptInAnyLang scriptBytes
      case scriptInAnyLang of
        Left _ -> throw $ SomeError "Error on deserializing script file"
        Right scriptAnyLang -> pure scriptAnyLang


validateScriptSupportedInEra' :: CardanoEra era
                             -> ScriptInAnyLang
                             -> IO (ScriptInEra era)
validateScriptSupportedInEra' era script@(ScriptInAnyLang lang _) =
    case toScriptInEra era script of
      Nothing -> throw $ SomeError "Error this script not supported."
      Just script' -> pure script'


scriptWitnessPolicyId' :: ScriptWitness witctx era -> PolicyId
scriptWitnessPolicyId' witness =
  case scriptWitnessScript witness of
    ScriptInEra _ script -> scriptPolicyId script


placeOnMarket conn [tokenStr,costStr] =do
        -- lockedNftValue <- unEither   eitherLockedValue
        -- sKey <-getDefaultSignKey
        -- ds <- unEither $ saleData (sKeyToPkh sKey)
        -- scriptDataHash <- unEither $ dataHash ds

        -- paramQueryResult<-queryNodeLocalState conn Nothing protocolParamsQuery
        -- let walletAddr=toAddressAny $ skeyToAddr sKey
        --     walletPkh=sKeyToPkh sKey
        -- pParam<-case paramQueryResult of
        --   Left af -> throw $ SomeError  "Acquire Failure"
        --   Right e -> case e of
        --     Left em -> throw $ SomeError "Missmatched Era"
        --     Right pp -> return pp

        -- let nftTxOut = TxOut marketCardanoApiAddress (TxOutValue MultiAssetInAlonzoEra lockedNftValue) (TxOutDatumHash ScriptDataInAlonzoEra scriptDataHash)
        -- minLovelace <- unEither $ calculateMinimumLovelace nftTxOut pParam
        -- putStrLn $ "min lovelace " ++ show minLovelace
        -- let lockedValue = lockedNftValue <> minLovelace
        -- utxos<-queryPaymentUtxosAndChange  conn lockedValue walletAddr
        -- putStrLn $ "Using Utxos " ++ show utxos
        -- let txIns = map utxosWithWitness utxos
        --     values = map utxosValue utxos
        --     totalValue = sumValue values
        --     changeValue = totalValue <> (negateValue lockedValue)

        -- alonzoWalletAddr<-unMaybe "Address not supported in alonzo era" $ anyAddressInEra AlonzoEra walletAddr

        putStrLn "ok"
        -- let txOuts = composeTxOuts alonzoWalletAddr changeValue lockedValue scriptDataHash
        --     body = makeTxBodyContent txIns txOuts pParam 0
        -- balancedTxBody <- unEither $ balanceTxBody body composeTxOuts txIns pParam alonzoWalletAddr changeValue lockedValue scriptDataHash
        -- void $ signAndSubmitTransaction conn sKey balancedTxBody

  where
    getSignKey content=deserialiseInputAnyOf [FromSomeType (AsSigningKey AsPaymentKey) id] [FromSomeType (AsSigningKey AsPaymentKey) id] content
    _witness=KeyWitness KeyWitnessForSpending

    requiredMemory = 700000000
    requiredSteps  = 700000000

    marketScript=PlutusScript PlutusScriptV1  $ marketScriptPlutus defaultMarket
    marketHash=hashScript   marketScript
    marketCardanoApiAddress=makeShelleyAddressInEra (Testnet (NetworkMagic 1097911063)) scriptCredential NoStakeAddress
    scriptCredential=PaymentCredentialByScript marketHash
    protocolParamsQuery= QueryInEra AlonzoEraInCardanoMode
                    $ QueryInShelleyBasedEra ShelleyBasedEraAlonzo QueryProtocolParameters
    dummyFee = Just $ Lovelace 0
    tx_mode body =TxInMode ( ShelleyTx ShelleyBasedEraAlonzo body )  AlonzoEraInCardanoMode

    utxosWithWitness (txin,txout) = (txin, BuildTxWith $ KeyWitness KeyWitnessForSpending)

    sumValue [] = lovelaceToValue $ Lovelace 0
    sumValue (x:xs) = x <> sumValue xs

    utxosValue (txin, TxOut _ (TxOutValue _ value) _) = value

    composeTxOuts alonzoWalletAddr walletValue scriptValue scriptDataHash= [
                      TxOut alonzoWalletAddr (TxOutValue MultiAssetInAlonzoEra (walletValue)) TxOutDatumHashNone,
                      TxOut marketCardanoApiAddress (TxOutValue MultiAssetInAlonzoEra scriptValue) (TxOutDatumHash ScriptDataInAlonzoEra scriptDataHash)
                      ]

    dataToJsonString :: (FromData a,ToJSON a) => a -> String
    dataToJsonString v=   fromText $ decodeUtf8  $ toStrict $ Data.Aeson.encode   $ toJSON v

    dataToHex :: (ToData  a) => a -> String
    dataToHex d= toHexString  $ serialise $  toData  d

    saleData:: PubKeyHash -> Either SomeError DirectSale
    saleData pkh = case splitByDot  of
      [cHexBytes,tBytes]     ->  case unHexBs cHexBytes of
        Just b  ->  case maybeCost of
            Just cost -> Right $ DirectSale pkh [] (toAc [b ,tBytes]) ( round (cost * 1000000)) Primary
            _ -> Left $ SomeError $ "Failed to parse \""++costStr++"\" as Ada value"
        _           -> Left $ SomeError $  "Failed to parse \""++ tokenStr ++ "\" : Invalid PolicyId"
      _         -> Left "Invalid format for Native token representation (Too many `.` character)"

    -- skey is the owner of the key who can withdraw from market
    dataHash ::DirectSale  -> Either SomeError (Hash ScriptData)
    dataHash sData = do
        let binary= serialise  $   toData  sData

        let hash=  fromStrict  $fromBuiltin $ sha3_256 $ toBuiltinBs $ toStrict  binary

        let cardanoHash=deserialiseFromRawBytes (AsHash AsScriptData) $ toStrict hash
        case cardanoHash of
          Nothing -> Left  "Datum Hash conversion from plutus api to cardano api failed"
          Just ha -> Right ha

    maybeCost:: Maybe Float
    maybeCost  = readMaybe costStr

    eitherLockedValue :: Either SomeError Value
    eitherLockedValue= case splitByDot  of
      [cHexBytes,tBytes]     ->  case unHexBs cHexBytes of
        Just policyBytes  -> case  deserialiseFromRawBytes AsPolicyId  policyBytes of
          Just policyId -> case deserialiseFromRawBytes AsAssetName tBytes of
            Just assetName -> Right  $ valueFromList  [ (AssetId policyId assetName , 1)]
            _ -> Left $ SomeError $ "TokenName couldn't be converrted to CardanoAPI type for value "++ show tBytes
          _ -> Left $ SomeError  $ "Policy Id  couldn't converted to CardanoAPI type  for value "++ show policyBytes
        _       -> Left $SomeError $ "Policy id is not hex string given value is :"++ show cHexBytes
      _         -> Left "Too many `.` character in tokenName"


    toAc [cBytes,tBytes]= assetClass (CurrencySymbol $ toBuiltinBs cBytes) (TokenName $ toBuiltinBs tBytes )

    toBuiltinBs :: ByteString -> BuiltinByteString
    toBuiltinBs  = toBuiltin

    splitByDot :: [ByteString]
    splitByDot=C.split  '.' $ encodeUtf8 . T.pack $ tokenStr


buyToken market@Market{mOperator, mPrimarySaleFee} conn [utxoId, datumStr] =do
  directSale  <- unEither  (saleData datumStr)
  paymentAsset <-unEither $ dsAssetId directSale
  sKey <-getDefaultSignKey
  operatorAddr <- unMaybe "Market pubKeyHash couldn't be converted to Cardano API address" $ pkhToMaybeAddr mOperator
  txInData <- unEither $ saleData datumStr
  paramQueryResult<-queryNodeLocalState conn Nothing protocolParamsQuery
  let walletAddr=toAddressAny $ skeyToAddr sKey
      walletPkh=sKeyToPkh sKey
      toPartyUtxo (pkh@(PubKeyHash binary),v) =case pkhToMaybeAddr pkh of
        Just addr -> Right $ singletonTxOut addr paymentAsset (Quantity v)
        _ -> Left $ SomeError $ "Party pubKeyHash couldn't be converted to Cardano API address :" ++ toHexString (fromBuiltin binary)
  partyUtxos<-unEither $ mapM toPartyUtxo ( dsPaymentValueList market directSale)
  (inputs,change) <-queryPaymentUtxosAndChange conn (lovelaceToValue  $ Lovelace 1) walletAddr
  pParam<-case paramQueryResult of
    Left af -> throw $ SomeError  "Acquire Failure"
    Right e -> case e of
      Left em -> throw $ SomeError "Missmatched Era"
      Right pp -> return pp
  alonzoWalletAddr<-unMaybe "Address not supported in alonzo era" $ anyAddressInEra AlonzoEra walletAddr
  let body =
          (TxBodyContent {
            txIns=map (\(a,b)->(a,BuildTxWith $ ScriptWitness ScriptWitnessForSpending $  plutusScriptWitness txInData)) inputs ,
            txInsCollateral=TxInsCollateral CollateralInAlonzoEra  [  ],
            txOuts=
                singletonTxOut operatorAddr paymentAsset (Quantity $ dsFee market directSale)
                  :
                partyUtxos,
            txFee=TxFeeExplicit TxFeesExplicitInAlonzoEra $ Lovelace 1000000,
            -- txValidityRange = (
            --     TxValidityLowerBound ValidityLowerBoundInAlonzoEra 0
            --     , TxValidityUpperBound ValidityUpperBoundInAlonzoEra 6969),
            txValidityRange=(TxValidityNoLowerBound,TxValidityNoUpperBound ValidityNoUpperBoundInAlonzoEra),
            txMetadata=TxMetadataNone ,
            txAuxScripts=TxAuxScriptsNone,
            txExtraScriptData=BuildTxWith TxExtraScriptDataNone ,
            txExtraKeyWits=TxExtraKeyWitnessesNone,
            txProtocolParams=BuildTxWith (Just  pParam),
            txWithdrawals=TxWithdrawalsNone,
            txCertificates=TxCertificatesNone,
            txUpdateProposal=TxUpdateProposalNone,
            txMintValue=TxMintNone,
            txScriptValidity=TxScriptValidityNone
          })
  case makeTransactionBody $ body of
    Left tbe ->
      throw $ SomeError $  "Tx Body has error : " ++  (show tbe)
    Right txBody -> do
      let tx = makeSignedTransaction [ makeShelleyKeyWitness txBody (WitnessPaymentKey sKey) ] (txBody) -- witness and txBody
      res <-submitTxToNodeLocal conn $  TxInMode tx AlonzoEraInCardanoMode
      case res of
        SubmitSuccess ->  do
          let v= getTxId txBody
          putStrLn "Transaction successfully submitted."
          putStrLn $ "TXId : "++ (show $ v)
        SubmitFail reason ->
          case reason of
            TxValidationErrorInMode err _eraInMode ->  print err
            TxValidationEraMismatch mismatchErr -> print mismatchErr

  where
    getSignKey content=deserialiseInputAnyOf [FromSomeType (AsSigningKey AsPaymentKey) id] [FromSomeType (AsSigningKey AsPaymentKey) id] content
    _witness=KeyWitness KeyWitnessForSpending

    requiredMemory = 700000000
    requiredSteps  = 700000000

    marketScript=PlutusScript PlutusScriptV1  $ marketScriptPlutus defaultMarket
    marketHash=hashScript   marketScript
    marketCardanoApiAddress::AddressInEra AlonzoEra
    marketCardanoApiAddress=makeShelleyAddressInEra (Testnet (NetworkMagic 1097911063)) scriptCredential NoStakeAddress
    scriptCredential=PaymentCredentialByScript marketHash

    plutusScriptWitness ::ToData a=> a-> ScriptWitness  WitCtxTxIn AlonzoEra
    plutusScriptWitness  d = PlutusScriptWitness
                            PlutusScriptV1InAlonzo
                            PlutusScriptV1
                            (marketScriptPlutus defaultMarket)
                            (ScriptDatumForTxIn $ fromPlutusData $ toData d) -- script data
                            (fromPlutusData $ toData Buy) -- script redeemer
                            (ExecutionUnits requiredSteps requiredMemory)
    protocolParamsQuery= QueryInEra AlonzoEraInCardanoMode
                    $ QueryInShelleyBasedEra ShelleyBasedEraAlonzo QueryProtocolParameters
    dummyFee = Just $ Lovelace 0
    tx_mode body =TxInMode ( ShelleyTx ShelleyBasedEraAlonzo body )  AlonzoEraInCardanoMode

    saleData:: String -> Either SomeError DirectSale
    saleData dataStr =do
      case head dataStr of
        '{' -> maybeToEither "JSON couldn't be parsed to DirectSale structure" (Data.Aeson.decode (fromString dataStr ))
        _    -> do
            bs<-maybeToEither  "Invalid Hex string for datum" (unHex dataStr)
            maybeToEither "Binary Data can't be parsed as directSale"  $ fromBuiltinData (toBuiltinData   $  toBuiltin  bs)


    singletonTxOutValue:: AssetId -> Quantity -> TxOutValue AlonzoEra
    singletonTxOutValue  a v =TxOutValue MultiAssetInAlonzoEra (valueFromList  [ (a , v)])

    singletonTxOut :: AddressInEra  AlonzoEra -> AssetId -> Quantity -> Cardano.Api.Shelley.TxOut AlonzoEra
    singletonTxOut  addr aId q = TxOut addr (singletonTxOutValue aId q) TxOutDatumHashNone


    dsAssetId::DirectSale -> Either SomeError AssetId
    dsAssetId DirectSale{dsAsset=AssetClass (CurrencySymbol c, TokenName t)}=
      case  deserialiseFromRawBytes AsPolicyId  (fromBuiltin c) of
          Just policyId -> case deserialiseFromRawBytes AsAssetName (fromBuiltin t) of
            Just assetName -> Right $ AssetId policyId assetName
            _ -> Left $ SomeError $ "TokenName couldn't be converrted to CardanoAPI type for value : 0x"++   toHexString (fromBuiltin t)
          _ -> Left $ SomeError  $ "Policy Id  couldn't converted to CardanoAPI type  for value : 0x"++ toHexString (fromBuiltin t)

    toBuiltinBs :: ByteString -> BuiltinByteString
    toBuiltinBs  = toBuiltin


marketScriptPlutus :: Market -> PlutusScript PlutusScriptV1
marketScriptPlutus market =PlutusScriptSerialised $ marketScriptBS market

marketScriptBS :: Market -> SBS.ShortByteString
marketScriptBS market = SBS.toShort . LBS.toStrict $ serialise script
  where
  script  = Plutus.unValidatorScript $ marketValidator market

writePlutusScript :: Integer -> FilePath -> PlutusScript PlutusScriptV1 -> SBS.ShortByteString -> IO ()
writePlutusScript scriptnum filename scriptSerial scriptSBS =
  do
  case Plutus.defaultCostModelParams of
        Just m ->
          let Alonzo.Data pData = toAlonzoData (ScriptDataNumber scriptnum)
              (logout, e) = Plutus.evaluateScriptCounting Plutus.Verbose m scriptSBS [pData]
          in case e of
                  Left evalErr -> print $ ("Eval Error" :: String) ++ show  evalErr
                  Right exbudget -> print  $ ("Ex Budget" :: String) ++ show exbudget
        Nothing -> error "defaultCostModelParams failed"
  result <- writeFileTextEnvelope filename Nothing scriptSerial
  case result of
    Left err -> print $ displayError err
    Right () -> return ()

runPayCommand::LocalNodeConnectInfo CardanoMode -> [String] -> IO()
runPayCommand conn [strAddr,lovelaceStr] =do
  paramQueryResult<-queryNodeLocalState conn Nothing protocolParamsQuery
  receiverAddr<- unMaybe "Address Unrecognized " $ deserialiseAddress AsAddressAny $ toText strAddr
  receiverAddrAlonzo <- unMaybe "Receiver address not supported in alonzo era" $ anyAddressInEra AlonzoEra receiverAddr
  sKey <-getDefaultSignKey
  let walletAddr=  skeyToAddrInEra sKey
  paymentDigit ::Integer <-unMaybe "Invalid value for lovelace" $ readMaybe lovelaceStr
  utxos<-queryUtxos conn  $toAddressAny $ skeyToAddr sKey

  let paymentValue = lovelaceToValue $ Lovelace   paymentDigit

  -- putStrLn $ "Using txin " ++ show _in
  -- putStrLn $ "Spending " ++  show out
  pParam<-case paramQueryResult of
    Left af -> throw $ SomeError  "Acquire Failure"
    Right e -> case e of
      Left em -> throw $ SomeError "Missmatched Era"
      Right pp -> return pp
  putStrLn "Something's fishy" 
  let balancedBody = mkBalancedBody pParam  utxos (TxBodyContent {
                      txIns=[],
                      txInsCollateral=TxInsCollateral CollateralInAlonzoEra  [  ],
                      txOuts=[TxOut receiverAddrAlonzo (TxOutValue MultiAssetInAlonzoEra paymentValue) TxOutDatumHashNone],
                        -- [TxOut alonzoAddr (TxOutValue MultiAssetInAlonzoEra (lovelaceToValue $ Lovelace 5927107)) TxOutDatumHashNone ],
                      txFee=TxFeeExplicit TxFeesExplicitInAlonzoEra  ( Lovelace 0),
                      txValidityRange=(TxValidityNoLowerBound,TxValidityNoUpperBound ValidityNoUpperBoundInAlonzoEra),
                      -- txValidityRange = (TxValidityLowerBound  ValidityLowerBoundInAlonzoEra 38698728,TxValidityUpperBound ValidityUpperBoundInAlonzoEra  38699728),
                      txMetadata=TxMetadataNone ,
                      txAuxScripts=TxAuxScriptsNone,
                      txExtraScriptData=BuildTxWith TxExtraScriptDataNone ,
                      txExtraKeyWits=TxExtraKeyWitnessesNone,
                      txProtocolParams=BuildTxWith (Just  pParam),
                      txWithdrawals=TxWithdrawalsNone,
                      txCertificates=TxCertificatesNone,
                      txUpdateProposal=TxUpdateProposalNone,
                      txMintValue=TxMintNone,
                      txScriptValidity=TxScriptValidityNone
                    })   (lovelaceToValue $ Lovelace 0) receiverAddrAlonzo

      --End Balance transaction body with fee
  case  balancedBody of
    Left tbe ->
      throw $ SomeError $  "Coding Error : Tx Body has error : " ++  (show tbe)
    Right txBody -> do
      let ins=case txBody of { ShelleyTxBody sbe (LedgerBody.TxBody ins _ _ _ _ _ _ _ _ _ _ _ _ ) scs tbsd m_ad tsv -> ins }
      putStrLn "Using inputs"
      mapM_ print ins
      let tx = makeSignedTransaction [ makeShelleyKeyWitness txBody (WitnessPaymentKey sKey) ] (txBody) -- witness and txBody
      res <-submitTxToNodeLocal conn $  TxInMode tx AlonzoEraInCardanoMode
      case res of
        SubmitSuccess ->  do
          let v= getTxId txBody
          putStrLn "Transaction successfully submitted."
          putStrLn $ "TXId : "++ (show $ v)
        SubmitFail reason ->
          case reason of
            TxValidationErrorInMode err _eraInMode ->  print err
            TxValidationEraMismatch mismatchErr -> print mismatchErr

  where
    _witness=KeyWitness KeyWitnessForSpending
    protocolParamsQuery= QueryInEra AlonzoEraInCardanoMode
                    $ QueryInShelleyBasedEra ShelleyBasedEraAlonzo QueryProtocolParameters
    dummyFee = Just $ Lovelace 0
    tx_mode body =TxInMode ( ShelleyTx ShelleyBasedEraAlonzo body )  AlonzoEraInCardanoMode
    handler e = putStrLn e
    catcher e = case e of
      SomeError _ ->Nothing
      _            -> Just "Node error or something"

    utxosWithWitness (txin,txout) = (txin, BuildTxWith $ KeyWitness KeyWitnessForSpending)

    utxosValue (txin, TxOut _ (TxOutValue _ value) _) = value


runPayCommand _ _ = putStrLn "Invalid no of args"

runConnectionTest :: LocalNodeConnectInfo CardanoMode -> IO ()
runConnectionTest  conn = do
  handleJust catcher handler ( getLocalChainTip conn >>=print )
  v<-queryNodeLocalState conn Nothing protocolParamsQuery

  pParam<-case v of
    Left af -> throw $ SomeError  "Acquire Failure"
    Right e -> case e of
      Left em -> throw $ SomeError "Missmatched Era"
      Right pp -> return pp

  putStrLn $ show pParam



  where
    protocolParamsQuery= QueryInEra AlonzoEraInCardanoMode
                    $ QueryInShelleyBasedEra ShelleyBasedEraAlonzo QueryProtocolParameters
    handler e = putStrLn e
    catcher e = case e of
      SomeError _  ->Nothing
      _            -> Just "Node error or something"


runBalanceCommand :: LocalNodeConnectInfo CardanoMode -> [Text] -> IO ()
runBalanceCommand conn args =do
  skey <-getDefaultSignKey
  let paymentCredential =   PaymentCredentialByKey  $ verificationKeyHash   $ getVerificationKey  skey
  addrs <- (case args of
      [] ->  do
          pure  [ toAddressAny   $ makeShelleyAddress (Testnet  (NetworkMagic 1097911063))  paymentCredential NoStakeAddress]
      as -> case mapMaybe (\x -> deserialiseAddress AsAddressAny x) ( as) of
          [] -> throw $ SomeError "Address couldn't be serialized"
          v  -> pure v)
  v2 <- queryNodeLocalState conn Nothing $ utxoQuery addrs
  balances <-case v2 of
    Left af -> throw $ SomeError $ "Acquire Failure "++ show af
    Right e -> case e of
      Left em  -> throw $ SomeError $  "Era missmatch thing just happened, has the time started running backwards!"
      Right uto -> pure $  uto
  let balance =  foldMap toValue $ toTxOut balances
  putStrLn $ "Wallet Address: "++( fromText $  serialiseToBech32 $ makeShelleyAddress (Testnet  (NetworkMagic 1097911063))  paymentCredential NoStakeAddress)
  putStrLn $ "Utxo Count :" ++(show $ length  $ toTxOut balances)
  putTextLn $ renderValuePretty balance
  where

  toTxOut (UTxO a) = Map.elems  a

  toValue ::Cardano.Api.Shelley.TxOut AlonzoEra -> Value
  toValue (TxOut _ v _) = case v of
    TxOutAdaOnly oasie lo -> lovelaceToValue lo
    TxOutValue masie va -> va

  utxoQuery qfilter= QueryInEra AlonzoEraInCardanoMode
                    $ QueryInShelleyBasedEra ShelleyBasedEraAlonzo (QueryUTxO (QueryUTxOByAddress (Set.fromList qfilter)) )

queryUtxos :: LocalNodeConnectInfo CardanoMode-> AddressAny -> IO (UTxO AlonzoEra)
queryUtxos conn addr=do
  a <-queryNodeLocalState conn Nothing $ utxoQuery [addr]
  case a of
    Left af -> throw $ SomeError $ show af
    Right e -> case e of
      Left em -> throw $ SomeError $ show em
      Right uto -> return uto

  where
  utxoQuery qfilter= QueryInEra AlonzoEraInCardanoMode
                    $ QueryInShelleyBasedEra ShelleyBasedEraAlonzo (QueryUTxO (QueryUTxOByAddress (Set.fromList qfilter)) )

querySufficientUtxo :: LocalNodeConnectInfo CardanoMode -> p -> AddressAny -> IO [(TxIn, Cardano.Api.Shelley.TxOut AlonzoEra)]
querySufficientUtxo conn value addr=queryUtxos conn addr <&>  toList
  where
    toList (UTxO m) = Map.toList m


queryUtxoList :: LocalNodeConnectInfo CardanoMode -> AddressAny -> IO [(TxIn, Cardano.Api.Shelley.TxOut AlonzoEra)]
queryUtxoList conn addr=queryUtxos conn addr <&>  toList
  where
    toList (UTxO m) = Map.toList m


queryPaymentUtxosAndChange :: LocalNodeConnectInfo CardanoMode-> Value -> AddressAny -> IO ([(TxIn, Cardano.Api.Shelley.TxOut AlonzoEra)], Value)
queryPaymentUtxosAndChange conn value addr=do
    allUtxos<-queryUtxos conn addr<&> toList

    pure (allUtxos  , foldMap ( toValue . snd) allUtxos <> negateValue value)

  where
    toTxOut (UTxO a) = Map.elems  a

    toValue ::Cardano.Api.Shelley.TxOut AlonzoEra -> Value
    toValue (TxOut _ v _) = case v of
      TxOutAdaOnly oasie lo -> lovelaceToValue lo
      TxOutValue masie va -> va
    toList (UTxO m) = Map.toList m


getWorkPath :: [FilePath] -> IO  FilePath
getWorkPath paths= do
  eitherHome <-try $ getEnv "HOME"
  case eitherHome of
    Left (e::IOError) -> throw $ SomeError "Can't get Home directory"
    Right home -> do
      pure $ joinPath  $  [home , ".cardano"] ++ paths

putTextLn :: Text -> IO ()
putTextLn v  = putStrLn  $ fromText v

localNodeConnInfo :: FilePath -> LocalNodeConnectInfo CardanoMode
localNodeConnInfo = LocalNodeConnectInfo (CardanoModeParams (EpochSlots 21600))  (Testnet  (NetworkMagic 1097911063))

readSignKey :: FilePath -> IO (SigningKey PaymentKey)
readSignKey file = do
  eitherSkey<-try  readSkeyFromFile
  case eitherSkey of
    Left (e::IOError )-> throw $ SomeError  $"There was error reading skey file"
    Right sk -> pure sk
  where
    readSkeyFromFile=do
      exists<-doesFileExist file
      if exists then pure () else throw (SomeError $ file ++ "  doesn't exist")
      content <-readBs file
      case getSignKey content of
        Left bde -> throw $ SomeError $ "Invalid sign key "++ show bde
        Right sk -> pure sk

    readBs:: FilePath -> IO ByteString
    readBs  = BS.readFile

    getSignKey content=deserialiseInputAnyOf [FromSomeType (AsSigningKey AsPaymentKey) id] [FromSomeType (AsSigningKey AsPaymentKey) id] content


getDefaultSignKey :: IO (SigningKey PaymentKey)
getDefaultSignKey= getWorkPath ["default.skey"] >>= readSignKey

skeyToAddr:: SigningKey PaymentKey -> Cardano.Api.Shelley.Address ShelleyAddr
skeyToAddr skey =
  makeShelleyAddress (Testnet  (NetworkMagic 1097911063))  credential NoStakeAddress
  where
    credential=PaymentCredentialByKey  $ verificationKeyHash   $ getVerificationKey  skey

skeyToAddrInEra ::  SigningKey PaymentKey -> AddressInEra AlonzoEra
skeyToAddrInEra skey=makeShelleyAddressInEra (Testnet  (NetworkMagic 1097911063))  credential NoStakeAddress
  where
    credential=PaymentCredentialByKey  $ verificationKeyHash   $ getVerificationKey  skey



sKeyToPkh:: SigningKey PaymentKey -> Plutus.PubKeyHash
sKeyToPkh skey= PubKeyHash (toBuiltin  $  serialiseToRawBytes  vkh)
  where
    vkh=verificationKeyHash   $ getVerificationKey  skey

pkhToMaybeAddr:: PubKeyHash -> Maybe (AddressInEra  AlonzoEra)
pkhToMaybeAddr (PubKeyHash pkh) =do
    key <- vKey
    Just $ makeShelleyAddressInEra  Mainnet (PaymentCredentialByKey key)  NoStakeAddress
  where
    paymentCredential _vkey=PaymentCredentialByKey _vkey
    vKey= deserialiseFromRawBytes (AsHash AsPaymentKey) $fromBuiltin pkh

-- addrToPkh :: AddressAny  -> Either SomeError PubKeyHash
-- addrToPkh addr =   do
--     bs <- maybeBinary
--     Right $ PubKeyHash $  toBuiltin bs
--   where
--     maybeBinary :: Either SomeError  ByteString
--     maybeBinary= case addr of
--       AddressByron ad -> Left "Deverloer doesn't know how to get PubKeyHash of byron address"
--       AddressShelley ad -> case ad of { ShelleyAddress net cre sr -> Right (  serialiseToRawBytes  cre) }

runGenerateKey :: IO ()
runGenerateKey = do
    file <- getWorkPath ["default.skey"]
    exists<-doesFileExist file
    if exists then throw (SomeError "default.skey File already exists") else pure ()
    key <- generateSigningKey AsPaymentKey
    writeResult <- writeFileTextEnvelope file (Just "market-cli operation key") key
    case writeResult of
      Left fe -> throw  $ SomeError $  "Error writing Key " ++ show fe
      Right x0 -> pure ()


runImportKey  :: [String] -> IO()
runImportKey [path] = do
  key <- readSignKey path
  file <- getWorkPath ["default.skey"]
  exists<-doesFileExist file
  if exists then throw (SomeError "default.skey File already exists") else pure ()
  writeFile file  $ fromText ( serialiseToBech32  key)
runImportKey _ = throw $ SomeError "import: To many arguments"

valueLte :: Value -> Value -> Bool
valueLte _v1 _v2= any (\(aid,Quantity q) -> q > lookup aid) (valueToList _v1) -- do we find anything that's greater than q
  where
    lookup x= case Map.lookup x v2Map of
      Nothing -> 0
      Just (Quantity v) -> v
    v2Map=Map.fromList $ valueToList _v2
    -- v1Bundle= case case valueToNestedRep _v1 of { ValueNestedRep bundle -> bundle} of
    --   [ValueNestedBundleAda v , ValueNestedBundle policy assetMap] ->LovelaceToValue v
    --   [ValueNestedBundle policy assetMap]

nullValue :: Value -> Bool
nullValue v = not $ any (\(aid,Quantity q) -> q>0) (valueToList v)






mkBalancedBody  pParams (UTxO utxoMap)  txbody inputSum walletAddr = 
    do
      let (inputs1,change1) =minimize txouts startingChange
          bodyContent1=modifiedBody inputs1 change1 startingFee
      txBody1 <-makeTransactionBody bodyContent1

      let fee1= evaluateTransactionFee pParams txBody1 1 0
          (inputs2,change2)= minimize txouts change1
          bodyContent2 =modifiedBody inputs2 change2 fee1
      makeTransactionBody bodyContent2
    where

  startingFee=Lovelace $ toInteger $ protocolParamTxFeeFixed pParams

  txouts=  Map.toList utxoMap
  utxosWithWitness (txin,txout) = (txin, BuildTxWith  $ KeyWitness KeyWitnessForSpending)


  minimize utxos remainingChange= case utxos of
    []     -> ([] ,remainingChange)
    (txIn,txOut):subUtxos -> if val`valueLte` remainingChange
            then minimize subUtxos newChange -- remove the current txOut from the list
            else (case minimize subUtxos remainingChange of { (tos, va) -> ((txIn,BuildTxWith $ KeyWitness KeyWitnessForSpending):tos,va) }) -- include txOut in result
          where
            val = txOutValueToValue $ txOutValue  txOut
            newChange= remainingChange <> negateValue val

  startingChange=(negateValue $ foldMap (txOutValueToValue  . txOutValue ) (txOuts txbody))  --outputs
                  <> (if  null (txIns txbody) then lovelaceToValue startingFee else inputSum) -- inputs
                  <> (foldMap (txOutValueToValue  . txOutValue) $  Map.elems utxoMap)

  utxoToTxOut (UTxO map)=Map.toList map

  txOutValueToValue :: TxOutValue era -> Value
  txOutValueToValue tv =
    case tv of
      TxOutAdaOnly _ l -> lovelaceToValue l
      TxOutValue _ v -> v

  txOutValue (TxOut _ v _) = v

  modifiedBody txins change fee= content
    where
      content=(TxBodyContent  {
            txIns=txins ++ txIns txbody,
            txInsCollateral=txInsCollateral txbody,
            txOuts=  if nullValue change
                  then txOuts txbody
                  else TxOut  walletAddr (TxOutValue MultiAssetInAlonzoEra change) TxOutDatumHashNone :txOuts txbody ,
              -- [TxOut alonzoAddr (TxOutValue MultiAssetInAlonzoEra (lovelaceToValue $ Lovelace 5927107)) TxOutDatumHashNone ],
            txFee=TxFeeExplicit TxFeesExplicitInAlonzoEra  fee,
            -- txValidityRange=(TxValidityNoLowerBound,TxValidityNoUpperBound ValidityNoUpperBoundInAlonzoEra),
            txValidityRange = txValidityRange txbody,
            txMetadata=txMetadata txbody ,
            txAuxScripts=txAuxScripts txbody,
            txExtraScriptData=txExtraScriptData txbody ,
            txExtraKeyWits=txExtraKeyWits txbody,
            txProtocolParams= txProtocolParams   txbody,
            txWithdrawals=txWithdrawals txbody,
            txCertificates=txCertificates txbody,
            txUpdateProposal=txUpdateProposal txbody,
            txMintValue=txMintValue txbody,
            txScriptValidity=txScriptValidity txbody
          })

