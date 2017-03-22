# Feature specifications:

# Individual dense features are represented with strings like "s1w".
typealias DFeature AbstractString

# DFvec is a String vector specifying a set of dense features.
typealias DFvec{T<:DFeature} Vector{T}

# Individual sparse features are specified using a vector of feature
# names indicating a conjunction, e.g. ["s0w", "s0p"]
typealias SFeature{T<:AbstractString} Vector{T}

# SFVec is an vector of SFeatures specifying a set of sparse features.
# e.g. [["sw"],["nw","np"]]
typealias SFvec{T<:SFeature} Vector{T}

# Fvec is a union of DFvec and SFvec, which specify dense and sparse
# features respectively.  The user controls what kind of features are
# generated by using the appropriate type of feature vector.
typealias Fvec Union{DFvec,SFvec}


"""

    features(p::Parser, s::Sentence, feats, [x, idx])

Return a feature vector given a [`Parser`](@ref) state, a
[`Sentence`](@ref), and a feature specification vector.  The last two
arguments (optional) can provide a preallocated output array and an
offset position in that array.

Primitive features are represented by strings of the following form:

    [sn]\d?([hlr]\d?)*[wvcpdLabAB]

The meaning of each character is described below. The letter i
represents an optional single digit integer. A default value is used
if i is not specified.

|char|meaning|
|:---|:------|
|si|i'th stack word, default i=0 means top|
|ni|i'th buffer word, default i=0 means first|
|hi|i'th degree head, default i=1 means direct head|
|li|i'th leftmost child, default i=1 means the leftmost child|
|ri|i'th rightmost child, default i=1 means the rightmost child|
|w|word|
|v|word vector (first half of wvec)|
|c|context vector (second half of wvec)|
|p|postag|
|d|distance to the right using encoding: 1,2,3,4,5-10,10+|
|L|dependency label (0 is ROOT or NONE)|
|a|number of left children.|
|b|number of right children.|
|A|set of left dependency labels|
|B|set of right dependency labels|

For example "sp" or "s0p" indicate the postag of the top stack word,
"n0lL" means the dependency label of the leftmost child of the first
buffer word, "s1d" is the s0s1 distance, "s0d" is the s0n0 distance.

The returned feature vector can be dense (`Vector{Float}`) or sparse
(`Vector{Int}` indicating non-zero positions in a sparse binary
vector).  The choice is marked by the type of the `feats` argument:
for dense output it should be a `Vector{String}`, for sparse output it
should be a `Vector{Vector{String}}`:

    ["s0v","n0lp","n1p"]  # dense feature spec
    [["sw"],["sw","sp"]]  # sparse feature spec

This allows sparse feature specifications to contain elements with
multiple primitive features indicating conjunctions. Some other
notable differences between dense and sparse features are:

* Dense vectors do not support "word", sparse vectors do not support "word vector" or "context vector".
* Sparse vectors represent number of children exactly, dense vectors use the encoding 0,1,...,8,9+.
* For dense features, `x` is a float matrix and `idx=1` is the column number to fill. For sparse features `x` is an int vector and `idx=0` is an offset.

"""
function features(p::Parser, s::Sentence, feats::DFvec,
                  x::AbstractMatrix=Array(wtype(s),flen(p,s,feats),1), 
                  xcol::Integer=1)
    if xcol > size(x,2); error("xcol > size(x,2)"); end
    wrows = wdim(s)             #11
    xrows = size(x,1)
    xtype = eltype(x)
    x1 = one(xtype)
    x[:,xcol] = zero(xtype)     #173
    nx = 0                      # last entry in x
    nv = wrows # >> 1             # size of word/context vector, assumes word vec and context vec concatenated
    nd = p.ndeps
    np = length(s.vocab.postags)
    nw = p.nword
    ldep,rdep,lset,rset = getdeps(p) #3775
    for f in feats                   #48
        a = getanchor(f,p,ldep,rdep) #1402
        fn = f[end]                  #642
        if fn == 'v'                 #234
            if a>0                   #91
                copy!(x, (xcol-1)*xrows+nx+1, s.vocab.wvecs, (s.word[a]-1)*wrows+1, nv) #331
            end; nx += nv       #5
        elseif fn == 'c'        #200
            error("Context vectors not implemented.")
            # if a>0              #122
            #     copy!(x, (xcol-1)*xrows+nx+1, s.vocab.wvec, (a-1)*wrows+nv+1, nv) #492
            # end; nx += nv       #6
        elseif fn == 'p'        #114
            if a>0              #159
                if s.postag[a] > np; error("postag out of bound"); end #210
                x[nx+s.postag[a], xcol] = x1 #839
            end; nx += np                    #5
        elseif fn == 'd'
            if a>0
                d = getrdist(f,p,a)
                if d>0; x[nx+(d>10?6:d>5?5:d), xcol] = x1; end
            end; nx += 6
        elseif fn == 'L'
            if a>0
                r = p.deprel[a]
                if r > nd; error("deprel out of bound"); end
                x[nx+1+r, xcol] = x1 # first bit for deprel=0 (ROOT)
            end; nx += (nd+1)
        elseif fn == 'a'
            if a>0
                if isassigned(ldep,a)
                    lcnt=length(ldep[a])
                    if lcnt > 9; lcnt = 9; end
                else
                    lcnt = 0
                end
                x[nx+1+lcnt, xcol] = x1 # 0-9
            end; nx += 10
        elseif fn == 'b'
            if a>0
                if isassigned(ldep,a)
                    rcnt=length(ldep[a])
                    if rcnt > 9; rcnt = 9; end
                else
                    rcnt = 0
                end
                x[nx+1+rcnt, xcol] = x1 # 0-9
            end; nx += 10
        elseif fn == 'A'
            if a>0 && isassigned(lset,a)
                copy!(x, (xcol-1)*xrows+nx+1, Array{wtype(s)}(lset[a]), 1, nd) #
            end; nx += nd
        elseif fn == 'B'
            if a>0 && isassigned(rset,a)
                copy!(x, (xcol-1)*xrows+nx+1, Array{wtype(s)}(rset[a]), 1, nd) #
            end; nx += nd
        elseif fn == 'w'
            error("Dense features do not support 'w'")
        else
            error("Unknown feature $(fn)") # 3
        end
    end
    nx == xrows || error("Bad feature vector length $nx != $xrows")
    return x
end

# Sparse feature extractor:

# TODO: change default idx=1.

function features(p::Parser, s::Sentence, feats::SFvec,
                  x::AbstractMatrix=Array(SFtype, length(feats), 1), xcol=1)
    if xcol > size(x,2); error("xcol > size(x,2)"); end
    deps = getdeps(p)
    SFhash = s.vocab.fdict
    @inbounds for i = 1:length(feats)
        f = feats[i]
        v = Array(Any, length(f))                             # TODO: get rid of alloc here?
        for j=1:length(f)
            v[j] = features1(p,s,f[j],deps...) #1023
        end
        x[i,xcol] = get!(SFhash, (f,v), 1+length(SFhash)) #7782 TODO: need a better hash function here
    end
    return x
end


# Here is where the actual feature lookup happens.  Similar to the
# dense lookup.  But does not have to convert everything to a number,
# can return strings etc.  Returns 'nothing' if target word does not
# exist or the feature is not available.

function features1(p::Parser, s::Sentence, f::String, ldep, rdep, lset, rset)
    a = getanchor(f,p,ldep,rdep)
    if a == 0; return nothing; end
    fn = f[end]
    if fn == 'w'; s.word[a]
    elseif fn == 'p'; s.postag[a]
    elseif fn == 'L'; p.deprel[a]
    elseif fn == 'a'; if isassigned(ldep,a); length(ldep[a]); else; 0; end
    elseif fn == 'b'; if isassigned(rdep,a); length(rdep[a]); else; 0; end
    elseif fn == 'A'; if isassigned(lset,a); lset[a]; else; nothing; end
    elseif fn == 'B'; if isassigned(rset,a); rset[a]; else; nothing; end
    elseif fn == 'd'; (d=getrdist(f,p,a); if d>10; 6; elseif d>5; 5; else; d; end)
    elseif fn == 'v'; error("Sparse features do not support 'v'")
    elseif fn == 'c'; error("Sparse features do not support 'c'")
    else error("Unknown feature letter $fn")
    end
end

function flen(p::Parser, s::Sentence, feats::SFvec)
    length(feats) # one integer per feature
end

function flen(p::Parser, s::Sentence, feats::DFvec)
    nx = 0
    nw = wdim(s)  # >> 1
    nd = p.ndeps
    np = length(s.vocab.postags)
    for f in feats
        nx += flen1(f[end], nw, nd, np) # 1129
    end
    return nx
end

function flen1(c::Char, nw::Int, nd::Int, np::Int)
    if c == 'v'; nw
    elseif c == 'c'; nw
    elseif c == 'p'; np
    elseif c == 'd'; 6
    elseif c == 'L'; (nd+1) # ROOT is not included in nd, TODO: fix this
    elseif c == 'a'; 10
    elseif c == 'b'; 10
    elseif c == 'A'; nd
    elseif c == 'B'; nd
    else error("Unknown feature character $c")
    end
end

# Utility functions to calculate the size of the feature matrix

xsize(p::Parser, s::Sentence, f::Fvec)=(flen(p,s,f),nmoves(p,s))
xsize(p::Parser, c::Corpus, f::Fvec)=(flen(p,c[1],f),nmoves(p,c))
xsize{T<:Parser}(p::Vector{T}, c::Corpus, f::Fvec)=xsize(p[1],c,f)
ysize(p::Parser, s::Sentence)=(nmoves(p),nmoves(p,s))
ysize(p::Parser, c::Corpus)=(nmoves(p),nmoves(p,c))
ysize{T<:Parser}(p::Vector{T}, c::Corpus)=ysize(p[1],c)

function getdeps{T<:Parser}(p::T)
    nw = p.nword
    nd = p.ndeps
    dr = p.deprel
    ldep = Array(Any,nw)
    rdep = Array(Any,nw)
    lset = Array(Any,nw)
    rset = Array(Any,nw)
    @inbounds for d=1:nw
        h=Int(p.head[d])
        if h==0
            continue
        elseif d<h
            if !isassigned(ldep,h)
                ldep[h]=[d]
                lset[h]=zeros(UInt8,nd) # falses(nd) is slower
                lset[h][dr[d]]=1
            else
                push!(ldep[h],d)
                lset[h][dr[d]]=1
            end
        elseif d>h
            if !isassigned(rdep,h)
                rdep[h]=[d]
                rset[h]=zeros(UInt8,nd)
                rset[h][dr[d]]=1
            else
                unshift!(rdep[h],d)
                rset[h][dr[d]]=1
            end
        else
            error("h==d")
        end
    end
    return (ldep,rdep,lset,rset)
end    

function getanchor(f::String, p::Parser, ldep, rdep)
    f1 = f[1]; f2 = f[2]; flen = length(f)
    if isdigit(f2)
        i = f2 - '0'            # index
        n = 3                   # next character
    else
        i = 0
        n = 2
    end
    a = 0                       # target word
    if f1 == 's'
        if (p.sptr - i >= 1) # 25
            a = Int(p.stack[p.sptr - i])             # 456
        end
    elseif f1 == 'n'
        if p.wptr + i <= p.nword
            a = p.wptr + i
        end
    else 
        error("feature string should start with [sn]")
    end
    if a==0; return 0; end
    while n < flen
        f1 = f[n]; f2 = f[n+1]
        if isdigit(f2)
            i = f2 - '0'
            n = n+2
        else
            i = 1
            n = n+1
        end
        if i <= 0
            error("hlr indexing is one based") # 3 [lrh] is one based, [sn] was zero based
        end
        if f1 == 'l'                              # 2
            if a > p.wptr; error("buffer words other than n0 do not have ldeps"); end # 252
            if isassigned(ldep,a) && i <= length(ldep[a])
                a = Int(ldep[a][i])
            else
                return 0
            end
        elseif f1 == 'r'
            if a >= p.wptr; error("buffer words do not have rdeps"); end
            if isassigned(rdep,a) && i <= length(rdep[a])
                a = Int(rdep[a][i])
            else
                return 0
            end
        elseif f1 == 'h'
            for j=1:i       # 5
                a = Int(p.head[a]) # 147
                if a == 0
                    return 0
                end
            end
        else 
            break
        end
    end
    if n != length(f); error("n!=length(f)"); end
    return a
end    

function getrdist(f::AbstractString, p::Parser, a::Integer)
    if f[1]=='s'
        if isdigit(f[2])
            i=f[2]-'0'
        else
            i=0
        end
        if i>0
            return p.stack[p.sptr - i + 1] - a
        elseif p.wptr <= p.nword
            return p.wptr - a
        else
            return 0
        end
    else
        return 0 # dist only defined for stack words
    end
end

