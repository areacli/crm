<?php

namespace App\Enums;

/**
 * Permissões do sistema, na numeração da matriz de permissões (matriz de permissões do projeto).
 * O valor guardado no banco é o nome em inglês; o número da matriz fica em number().
 */
enum Permission: string
{
    case ViewPortfolio = 'view_portfolio';
    case UploadImports = 'upload_imports';
    case ConfirmImports = 'confirm_imports';
    case ChangeSettings = 'change_settings';
    case UploadPayments = 'upload_payments';
    case ConfirmPayments = 'confirm_payments';
    case RecordContactAttempts = 'record_contact_attempts';
    case VoidOthersContactAttempts = 'void_others_contact_attempts';
    case ManageContactResults = 'manage_contact_results';
    case ManageUsers = 'manage_users';
    case ManageProfiles = 'manage_profiles';
    case EditCustomerRegistry = 'edit_customer_registry';
    case HandleDataSubjectRights = 'handle_data_subject_rights';
    case ChangeFinancialPolicies = 'change_financial_policies';
    case CancelPaymentPromises = 'cancel_payment_promises';
    case NegotiateAgreements = 'negotiate_agreements';
    case AdministerAgreements = 'administer_agreements';

    /** Número da permissão na matriz (1 a 17). */
    public function number(): int
    {
        return array_search($this, self::cases(), true) + 1;
    }

    public function label(): string
    {
        return __('permissions.'.$this->value);
    }
}
