<?php

namespace App\Enums;

/** Como os títulos a vencer aparecem nos totais, por credor (R20). */
enum UpcomingDisplay: string
{
    case Separate = 'separate';
    case Summed = 'summed';
    case DetailOnly = 'detail_only';
}
