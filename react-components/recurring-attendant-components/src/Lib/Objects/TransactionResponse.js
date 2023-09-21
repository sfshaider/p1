/*
this.setAuthorizationCode(trans, transData['authorization_code']);
this.setCVVResponse(trans, transData['cvv_response']);
this.setAVSResponse(trans, transData['avs_response']);
this.setMessage(trans, transData['message']);
this.setStatus(trans, transData['status']);
this.setMerchantTransactionID(trans, transData['merchant_transaction_id']);
this.setErrors(trans, transData['errors']);
*/

class TransactionResponse {
    constructor(transaction, responseData) {
        if (!transaction) {
            throw new Error("Transaction must be defined when constructing a TransactionResponse");
        }
        this.transaction = transaction;
        this.responseData.auth = responseData.authorizationCode;
        this.responseData.cvvResponse = responseData.cvvResponse;
        this.responseData.avsResponse = responseData.avsResponse;
        this.responseData.message = responseData.message;
        this.responseData.status = responseData.status;
        this.responseData.errors = responseData.errors;
        this.responseData.orderID = responseData.orderID;
        this.responseData.transactionDateTime = responseData.transactionDateTime;
    }

    responseData = {};

    getAuthorizationCode = () => {
        return this.responseData.authorizationCode;
    };

    getCVVResponse = () => {
        return this.responseData.cvvResponse;
    };

    getAVSResponse = () => {
        return this.responseData.avsResponse;
    };

    getMessage = () => {
        return this.responseData.message;
    };

    getStatus = () => {
        return this.responseData.status;
    };

    getErrors = () => {
        return this.responseData.errors;
    };

    getOrderID = () => {
        return this.responseData.orderID
    };

    getDateTime = () => {
        return this.responseData.transactionDateTime
    };
}

export default TransactionResponse;