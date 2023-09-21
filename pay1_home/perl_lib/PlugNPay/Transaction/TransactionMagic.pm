package PlugNPay::Transaction::TransactionMagic;
# this is to do all the random things that we do for compatibility with the existing system.

use strict;

use PlugNPay::Features;
use PlugNPay::GatewayAccount;

sub Confundo {
  # Pronunciation: kon-fun-doh
  # Description: Causes the victim to become confused, befuddled, overly forgetful and prone to follow simple orders without thinking about them.
  # Seen/mentioned: First mentioned in Prisoner of Azkaban, when Severus Snape suggests that Harry and Hermione had been Confunded to believe Sirius Black's claim to innocence.[PA Ch.21] 
  #                 In Goblet of Fire, it is suggested that a powerful Confundus Charm is responsible for the Goblet choosing a fourth Triwizard contestant.[GF Ch.17] 
  #                 It is first seen in action when Hermione uses it on Cormac McLaggen during Quidditch tryouts in Half-Blood Prince.[HBP Ch.11]

  my $transaction = shift;

  # some commonly used magic ingredients
  my $account = $transaction->getGatewayAccount();
  my $accountData = new PlugNPay::GatewayAccount($account);
  my $features = new PlugNPay::Features($account,'general');

  my $isBusinessCard = '';
  my $businessCardType = '';
  if ($transaction->getTransactionPaymentType() eq 'credit') {
    $isBusinessCard = $transaction->getCreditCard()->isBusinessCard();
    $businessCardType = $transaction->getCreditCard()->isBusinessCard();
  }



  #  _______  _______  _______  _______           _       _________ _______ 
  # (  ___  )(  ____ \(  ____ \(  ___  )|\     /|( (    /|\__   __/(  ____ \
  # | (   ) || (    \/| (    \/| (   ) || )   ( ||  \  ( |   ) (   | (    \/
  # | (___) || |      | |      | |   | || |   | ||   \ | |   | |   | (_____ 
  # |  ___  || |      | |      | |   | || |   | || (\ \) |   | |   (_____  )
  # | (   ) || |      | |      | |   | || |   | || | \   |   | |         ) |
  # | )   ( || (____/\| (____/\| (___) || (___) || )  \  |   | |   /\____) |
  # |/     \|(_______/(_______/(_______)(_______)|/    )_)   )_(   \_______)
  #                                                                        

  # Account: Boudin
  if ($account eq 'boudin') {
    if ($businessCardType ne '') {
      $transaction->addTransactionFlag('level3');
    }
  } 
  # End Boudin


  #  _______  _______  _______  _______  _        _        _______  _______  _______ 
  # (  ____ )(  ____ \(  ____ \(  ____ \( \      ( \      (  ____ \(  ____ )(  ____ \
  # | (    )|| (    \/| (    \/| (    \/| (      | (      | (    \/| (    )|| (    \/
  # | (____)|| (__    | (_____ | (__    | |      | |      | (__    | (____)|| (_____ 
  # |     __)|  __)   (_____  )|  __)   | |      | |      |  __)   |     __)(_____  )
  # | (\ (   | (            ) || (      | |      | |      | (      | (\ (         ) |
  # | ) \ \__| (____/\/\____) || (____/\| (____/\| (____/\| (____/\| ) \ \__/\____) |
  # |/   \__/(_______/\_______)(_______/(_______/(_______/(_______/|/   \__/\_______)
  # 

  # Reseller: Vermont/Vermont2
  if ($accountData->getReseller() =~ /^vermont2?$/) {
    if ($accountData->getCardProcessor() eq 'paytechtampa' && $transaction->hasTransFlag('recurring')) {
      $transaction->addTransFlag('moto');
    }
  }


  #  _______  _______  _______  _______  _______  _______  _______  _______  _______  _______ 
  # (  ____ )(  ____ )(  ___  )(  ____ \(  ____ \(  ____ \(  ____ \(  ___  )(  ____ )(  ____ \
  # | (    )|| (    )|| (   ) || (    \/| (    \/| (    \/| (    \/| (   ) || (    )|| (    \/
  # | (____)|| (____)|| |   | || |      | (__    | (_____ | (_____ | |   | || (____)|| (_____ 
  # |  _____)|     __)| |   | || |      |  __)   (_____  )(_____  )| |   | ||     __)(_____  )
  # | (      | (\ (   | |   | || |      | (            ) |      ) || |   | || (\ (         ) |
  # | )      | ) \ \__| (___) || (____/\| (____/\/\____) |/\____) || (___) || ) \ \__/\____) |
  # |/       |/   \__/(_______)(_______/(_______/\_______)\_______)(_______)|/   \__/\_______)
  #

  # Processor: Mercury
  if ($accountData->getCardProcessor() eq 'mercury' && defined $transaction->getGiftCard() && $transaction->getCreditCard()->getNumber() eq '') {
    # copy the gift card number over to the card number # No option for split payments?
    my $giftCardNumber = $transaction->getGiftCard()->getNumber();
    my $giftCardCVV    = $transaction->getGiftCard()->getSecurityCode();
    $transaction->getCreditCard()->setNumber($giftCardNumber);
    $transaction->getCreditCard()->setSecurityCode($giftCardCVV);
    $transaction->addTransFlag('gift');
  }
    
  

}

1;
