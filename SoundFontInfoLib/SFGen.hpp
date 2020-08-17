// Copyright © 2020 Brad Howes. All rights reserved.

#pragma once

#include "BinaryStream.hpp"
#include "SFGenerator.hpp"
#include "SFGenTypeAmount.hpp"

namespace SF2 {

/**
 Memory layout of a 'pgen'/'igen' entry. The size of this is defined to be 4. Each instance represents a generator
 configuration for a specific SFGenerator.
 */
struct SFGen {
    static constexpr size_t size = 4;

    SFGenerator sfGenOper;
    SFGenTypeAmount genAmount;

    SFGen(BinaryStream& is) { is.copyInto(this); }
    
    void dump(const std::string& indent, int index) const
    {
        std::cout << indent << index << ": " << sfGenOper.name() << " setting: " << sfGenOper.dump(genAmount)
        << std::endl;
    }
};

}