{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module HttpEndpoints where

-- import Cardano.Node.Cli (cliDefaultConfig, tip, NodeCliConfig)
-- import Cardano.Transaction (CardanoTransaction (CardanoTransaction), signTx, submitTx)
import Control.Exception
  ( Exception,
    IOException,
    catch,
    throw,
  )
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Trans.Reader (ReaderT (runReaderT))
import Data.Aeson (FromJSON, ToJSON, decode)
import Data.String.Conversions
  ( ConvertibleStrings (convertString),
  )
import Data.Typeable (Proxy (..))
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Network.HTTP.Media ((//), (/:))
import Servant
import Cli
-- import Wallet.Api
--   ( CreateWalletParam,
--     Wallet,
--     createWallet,
--     getWalletById,
--     getWalletKey,
--     listWallets, getFunds
--   )

data JsonRaw

type HttpAPI =
  "tip" :> Get '[JSON] String
    -- :<|> "wallet" :> ReqBody '[JSON] CreateWalletParam :> Put '[JSON] Wallet
    -- :<|> "wallet" :> Get '[JSON] [Wallet]
    -- :<|> "wallet" :> Capture "id" UUID :> Get '[JSON] (Maybe Wallet)
    -- :<|> "wallet" :> Capture "id" UUID :> "vkey" :> Get '[JsonRaw] (Maybe String)
    -- :<|> "wallet" :> Capture "id" UUID :> "signTx" :> ReqBody '[JSON] CardanoTransaction :> Post '[JSON] CardanoTransaction
    -- :<|> "wallet" :> Capture "id" UUID :> "funds" :> Get '[JsonRaw] (Maybe String)
    
    -- :<|> "transaction" :> "submit" :> ReqBody '[JSON] CardanoTransaction :> PostNoContent
    -- :<|> 
    -- "try" :> Get '[JSON] String


instance Accept JsonRaw where
  contentType _ = "application" // "json" /: ("charset", "utf-8")

instance MimeRender JsonRaw String where
  mimeRender _ = convertString 

instance MimeRender JsonRaw (Maybe String) where
  mimeRender _ (Just s) = convertString s
  mimeRender _ Nothing = ""


server :: Server HttpAPI
server = 
    handleTip 
-- :<|> handleCreateWallet :<|> handleListWallets :<|> handleGetWallet :<|> handleGetPubKey :<|> handleSignTx 
--                    :<|> handleGetFunds :<|> handleSubmitTx 
                    --   :<|> 
                      -- handleTry
  where
    -- handleTry :: Handler String
    -- handleTry = do
    --   return "ok"
      
    -- handleSubmitTx :: CardanoTransaction -> Handler NoContent
    -- handleSubmitTx tx = runReader (submitTx tx) >> return NoContent

    -- handleGetFunds :: UUID -> Handler (Maybe String)
    -- handleGetFunds = runReader . getFunds

    -- handleSignTx :: UUID -> CardanoTransaction -> Handler CardanoTransaction
    -- handleSignTx uuid = runReader . signTx uuid

    -- handleGetPubKey :: UUID -> Handler (Maybe String)
    -- handleGetPubKey uuid = liftIO $ runReaderT (getWalletKey uuid "payment.vkey") cliDefaultConfig

    -- handleGetWallet :: UUID -> Handler (Maybe Wallet)
    -- handleGetWallet uuid = liftIO $ runReaderT (getWalletById uuid) cliDefaultConfig

    -- handleListWallets :: Handler [Wallet]
    -- handleListWallets = liftIO $ runReaderT listWallets cliDefaultConfig

    -- handleCreateWallet :: CreateWalletParam -> Handler Wallet
    -- handleCreateWallet cwp = liftIO $ runReaderT (createWallet cwp) cliDefaultConfig

    handleTip :: Handler String
    handleTip = do
      string <- liftIO $ runReaderT readTip ()
      return string

    -- runReader :: ReaderT NodeCliConfig IO a -> Handler a
    -- runReader m = liftIO $ runReaderT m cliDefaultConfig

proxyAPI :: Proxy HttpAPI
proxyAPI = Proxy

app :: Application
app = serve proxyAPI server