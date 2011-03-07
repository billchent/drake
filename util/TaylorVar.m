classdef TaylorVar
% does inline autodiff
% overloads operators: http://www.mathworks.com/help/techdoc/matlab_oop/br02znk-1.html  

% the internal representation is 
% m=prod(size(f)), n=prod(size(x));
% df{o} is a m x n^o sparse matrix , where e.g. 
%        d^2 f(i,j)/dx_k dx_l =
%             df{o}(sub2ind(obj.dim,i,j),sub2ind([n n],k,l))

  properties
    f   % value at the nominal point
    df  % size(df{i}) is [size(f),repmat(size(x),1,i)]
    dim % size(f) - since I store things locally as a column vector
    nX   % size(x,1)
  end
  
  methods
    function obj=TaylorVar(f,df)
      obj.f = f(:);
      obj.dim = size(f);
      obj.df = df;
      obj.nX = size(df{1},2);
    end
    
    function varargout=eval(obj)
      varargout{1}=reshape(obj.f,obj.dim);
      
      for i=2:min(nargout,length(obj.df)+1)
        varargout{i}=obj.df{i-1};
      end
     
      % note: would love to reshape the df's into ND arrays, but matlab
      % can't handle sparse ND arrays.  and making them full could be very
      % inefficient!
    end
    
    function p = getmsspoly(obj,p_x)
      if (~isvector(p_x)) error('p_x should be a vector'); end
      if (length(obj.dim)>2) error('msspolys are not defined for ND arrays'); end
      p_x=p_x(:); % make sure p_x is a column vector
      
      p=reshape(obj.f,obj.dim);
      nX=obj.nX;
      x=1;
      for o=1:length(obj.df)
        % x needs to be nX^o-by-1 
        x=reshape(x(:)*p_x',nX^o,1)/o;
        p=p+reshape(obj.df{o}*x,obj.dim(1),obj.dim(2));
      end
    end
    
    function varargout=size(obj,dim)
      if (nargin>1)  
        varargout{1}=obj.dim(dim);
      elseif (nargout==1)
        varargout{1}=obj.dim;
      else
        N=nargout;
        NDIMS=length(obj.dim);
        for i=1:N
          if (i>NDIMS) varargout{i}=1;
          else varargout{i}=obj.dim(i);
          end
        end
        if (N<NDIMS)
          vargout{N}=prod(obj.dim(N:end));
        end
      end        
    end
    function lastind=end(obj,k,n)
      % end called as part of the kth index of n indices
      % 'help end' was the only way i found documentation on this
      if (n>length(obj.dim)) error('dimension mismatch'); end 
      lastind=obj.dim(k);
    end
    function obj=repmat(obj,M,N)
      if nargin == 2
        if isscalar(M)
          siz = [M M];
        else
          siz = M;
        end
      else
        siz = [M N];
      end
      f_ind=1:length(obj.f);
      new_f_ind=repmat(reshape(f_ind,obj.dim),siz);
      obj.f=reshape(obj.f(new_f_ind),[],1);
      obj.dim=size(new_f_ind);
      for o=1:length(obj.df)
        obj.df{o}=obj.df{o}(new_f_ind,:);
      end
    end
    function obj=reshape(obj,varargin)
      if (nargin==2)
        siz=varargin{1};
      else
        siz=[varargin{:}];
      end
      if (prod(siz)~=prod(obj.dim))
        error('the number of elements must not change');
      end
      obj.dim=siz;
    end
    
    function a=plus(a,b)
      if (~isa(a,'TaylorVar'))% then b is the TaylorVar.
        tmp=a; a=b; b=tmp;    % switch them (so we have less cases below)
      end
        
      if (isa(b,'TaylorVar'))
        if (a.nX~=b.nX) 
          error('orders don''t match'); 
        end
        if (any(a.dim~=b.dim)) 
          error('dimensions don''t match'); 
        end
        if (length(a.df)~=length(b.df)) error('orders don''t match'); end
        a.f=a.f + b.f;
        for o=1:length(a.df)
          a.df{o}=a.df{o}+b.df{o};
        end
      else  % b is a constant
        a.f=a.f+b;
        % a.df doesn't change
      end
    end
    function tv=minus(a,b)
      tv=plus(a,uminus(b));
    end
    function a=uminus(a)
      a.f=-a.f;
      for o=1:length(a.df)
        a.df{o}=-a.df{o};
      end
    end
    function a=uplus(a)
      % intentionally empty
    end
    function a=times(a,b)  % .*
      if (~isa(a,'TaylorVar'))% then b is the TaylorVar.
        tmp=a; a=b; b=tmp;    % switch them (so we have less cases below)
      end
      
      if (isa(b,'TaylorVar'))
        a.f=a.f .* b.f;
        for o=1:length(a.df)
          a.df{o}=a.df{o}.*repmat(b.f,1,a.nX^o) + repmat(a.f,1,a.nX^o).*b.df{o};
        end
      else
        b=b(:);
        a.f=a.f.*b;
        for o=1:length(a.df)
          a.df{o}=a.df{o}.*repmat(b,1,a.nX^o);
        end
      end
    end
    function a=mtimes(a,b)  % only allowed for scalars and 2D matrices
      if (~isa(a,'TaylorVar'))  % then only b is a TaylorVar
        [m,k] = size(a); n=b.dim(2);
        if (m==1 && k==1) % handle scalar case
          f = a*b.f;
          for o=1:length(b.df), b.df{o}=a*b.df{o}; end
        else
          f = a*reshape(b.f,b.dim); 
          for o=1:length(b.df)
            b.df{o} = reshape(a*reshape(b.df{o},k,n*b.nX^o),m*n,b.nX^o);
          end
        end
        a=b;
        a.f=f(:); a.dim=size(f);
      elseif (~isa(b,'TaylorVar')) % then only a is a TaylorVar
        m=a.dim(1); [k,n] = size(b); 
        if (k==1 && n==1) % handle scalar case
          f = a.f*b;
          for o=1:length(a.df), df{o}=a.df{o}*b; end
        else
          f = reshape(a.f,a.dim)*b; 
          for o=1:length(a.df)  % note: this one is less efficient because I have to repmat b below
            a.df{o} = reshape(reshape(a.df{o},m,k*obj.nX^o)*repmat(b,obj.nX^o,1),m*n,obj.nX^o);
            error('this is not correct.  need blkdiag.  see below');
          end
        end
        a.f=f(:); tv.dim=size(f);
      else % both are TaylorVars
        f = reshape(a.f,a.dim)*reshape(b.f,b.dim);
        if (length(a.df)<1 || length(b.df)<1) error('shouldn''t get here'); end
        % length of a.df and b.df should be >0 to get through the previous cases

        % want dcdx = dadx*b + a*dbdx.  diff(a) gives dadx, but will be >2D for matrices, 
        % so i have to handle the multiplies properly (as above)
        % dcdx is size [ma,nb,nX]
        ma=a.dim(1); na=a.dim(2); mb=b.dim(1); nb=b.dim(2); nX=a.nX;
% this version works, but is expensive       
        btmp = repmat({reduceOrder(b)},1,nX);
        dcdx = reshape(reshape(diff(a),ma,na*nX)*blkdiag(btmp{:}),[ma,nb,nX]) + ...
          reshape(reduceOrder(a)*reshape(diff(b),mb,nb*nX),[ma,nb,nX]);
% trying this version instead:
%        dcdx=reshape(reduceOrder(a)*reshape(diff(b),mb,nb*nX),[ma,nb,nX]);
%        da=diff(a);rb=reduceOrder(b);
%        for i=1:nX, dcdx(:,:,i)=dcdx(:,:,i)+da(:,:,i)*rb; end
% end new version        
        if (isa(dcdx,'TaylorVar'))
          a=int(dcdx,f);
        else
          dcdx = reshape(dcdx,[],nX);
          a=TaylorVar(f,{dcdx});
        end
      end
    end
    function tv=rdivide(a,b)
      error('not implemented yet');
    end 
    function tv=ldivide(a,b)
      error('not implemented yet');
    end   
    function a=mrdivide(a,b)
      if (~isa(b,'TaylorVar')) % then a is a TaylorVar, b is a const
        if (isscalar(b))
          a.f=a.f/b;
          for o=1:length(a.df), a.df{o}=a.df{o}/b; end
        else
          error('not implemented yet');
        end          
      else
        error('not implemented yet');
      end
    end
    function tv=inv(a)
      % use d/dq inv(H(q)) = - inv(H(q)) [d/dq H(q)] inv(H(q)) 
      if (length(a.dim)>2) error('only for 2D matrices'); end
      [m,n]=size(a);nX=a.nX;
      if (m~=n) error('only for square matrices'); end
      f = inv(reshape(a.f,a.dim));
      inva = inv(reduceOrder(a));
      tmp=repmat({inva},1,nX);
      df = -reshape(inva*reshape(diff(a),m,n*nX)*blkdiag(tmp{:}),m,n,nX);
      if (isa(df,'TaylorVar'))
        tv=int(df,f);
      else
        df = reshape(df,[],nX);
        tv=TaylorVar(f,{df});
      end
    end
    
    function tv=mldivide(a,b)
      tv=inv(a)*b;
      % todo: could make this better (more efficient/accurate?) if I handle
      % all the cases to use the actual \ call.
    end   
    function tv=power(a,b)
      error('not implemented yet');
    end   
    function tv=mpower(a,b)
      error('not implemented yet');
    end
    
    function ctranspose(a)
      error('not implemented yet');
    end
    function transpose(a)
      error('not implemented yet');
    end
    
%    function display(a)
%    end

    function tv = horzcat(varargin)
      % find the index of the first TaylorVar
      for i=1:length(varargin), if (isa(varargin{i},'TaylorVar')), obj=varargin{i}; break; end; end
      nX=obj.nX; order=length(obj.df);
      
      f=[];
      for o=1:order, df{o}=sparse(0,0); end
      
      for i=1:length(varargin)
        if (isa(varargin{i},'TaylorVar'))
          % figure out indices where the new data will be inserted:
          oldtag=zeros(size(f));
          newtag=ones(varargin{i}.dim);
          tags=[oldtag,newtag];
          oldinds=find(~tags(:));
          inds=find(tags(:));
          
          % now insert the data
          f=[f,reshape(varargin{i}.f,varargin{i}.dim)];
          if (varargin{i}.nX ~=nX) error('dimension mismatch'); end
          if (length(varargin{i}.df) ~= order) error('order mismatch'); end
          for o=1:order
            df{o}(oldinds,:)=df{o};
            df{o}(inds,:)=varargin{i}.df{o};
          end
        else  % vertcat in a const
          % figure out indices where the new data will be inserted:
          oldtag=zeros(size(f));
          newtag=ones(size(varargin{i}));
          tags=[oldtag,newtag];
          oldinds=find(~tags(:));
          inds=find(tags(:));

          % now insert the data
          f=[f,varargin{i}];
          n=prod(size(varargin{i}));
          for o=1:order
            df{o}(oldinds,:)=df{o};
            df{o}(inds,:)=sparse(n,nX^o);
          end
        end
      end
      tv=TaylorVar(f,df);
    end
    function tv = vertcat(varargin)
      % find the index of the first TaylorVar
      for i=1:length(varargin), if (isa(varargin{i},'TaylorVar')), tvi=i; break; end; end
      nX=varargin{tvi}.nX; order=length(varargin{tvi}.df);
      
      f=[];
      for o=1:order, df{o}=sparse(0,0); end
      
      for i=1:length(varargin)
        if (isa(varargin{i},'TaylorVar'))
          % figure out indices where the new data will be inserted:
          oldtag=zeros(size(f));
          newtag=ones(varargin{i}.dim);
          tags=[oldtag;newtag];
          oldinds=find(~tags(:));
          inds=find(tags(:));
          
          % now insert the data
          f=[f;reshape(varargin{i}.f,varargin{i}.dim)];
          if (varargin{i}.nX ~=nX) error('dimension mismatch'); end
          if (length(varargin{i}.df) ~= order) error('order mismatch'); end
          for o=1:order
            df{o}(oldinds,:)=df{o};
            df{o}(inds,:)=varargin{i}.df{o};
          end
        else  % vertcat in a const
          % figure out indices where the new data will be inserted:
          oldtag=zeros(size(f));
          newtag=ones(size(varargin{i}));
          tags=[oldtag;newtag];
          oldinds=find(~tags(:));
          inds=find(tags(:));

          % now insert the data
          f=[f;varargin{i}];
          n=prod(size(varargin{i}));
          for o=1:order
            df{o}(oldinds,:)=df{o};
            df{o}(inds,:)=sparse(n,nX^o);
          end
        end
      end
      tv=TaylorVar(f,df);
    end
    
    function obj = subsref(obj,s)
      f=subsref(reshape(obj.f,obj.dim),s);
      obj.dim=size(f);
      obj.f=f(:);

      % figure out indices corresponding to s
      tags=zeros(obj.dim);
      subsasgn(tags,s,1);
      ind=find(tags(:));

      % extract the relavent gradients
      for o=1:length(obj.df)
        obj.df{o}=obj.df{o}(ind,:);
      end
    end
    
    function a=subsasgn(a,s,b)
      a.f=subsasgn(a.f,s,b.f);

      tags=zeros(a.dim);
      subsasgn(tags,s,1);
      ind=find(tags(:));
      if (isa(b,'TaylorVar'))
        for o=1:length(a.df)
          a.df{o}(ind,:)=b.df{o};
        end
      else % b is a const
        for o=1:length(a.df)
          a.df{o}(ind,:)=0;
        end
      end
    end
    function tv=subindex(a)
      error('not implemented yet');
    end
    
    function tv=diff(obj)  % removes one order  (tv.f=obj.df{1}, etc)
      f=reshape(full(obj.df{1}),[obj.dim,obj.nX]);
      m=prod(obj.dim); n=obj.nX;
      if (length(obj.df)>1)
        for o=2:length(obj.df)
          df{o-1}=reshape(obj.df{o},m*n,n^(o-1));
        end
        tv=TaylorVar(f,df);
      else
        tv=f;
      end
    end
    function tv=int(obj,f) % tv.f=f tv.df{1}=obj.f tv.df{2}=obj.df{1}, etc
      dim=size(f);
      if (obj.dim(end)~=obj.nX) 
        error('dimension mismatch'); 
      end
      df{1}=reshape(sparse(obj.f),[prod(dim),obj.nX]);
      m=prod(obj.dim(1:end-1)); n=obj.nX;
      for o=1:length(obj.df)
        df{o+1}=reshape(obj.df{o},[m,n^(o+1)]);
      end
      tv=TaylorVar(f,df);
    end
    function obj=reduceOrder(obj,order)
      if (nargin<2) order=1; end
      if (order>=length(obj.df)) % then just return f as a double (or whatever)
        obj=reshape(obj.f,obj.dim);
      else
        obj.df = {obj.df{1:end-order}};
      end
    end
    function tv=elementwise(obj,fun,dfun)
      f=fun(obj.f);
      if (length(obj.df)>0)
        df=diff(obj); dim=size(df);
        dfsub=repmat(dfun(reduceOrder(obj)),[1,dim(2:end)]).*df;
%        dfsub=diag(dfun(reduceOrder(obj)))*diff(obj);
        if (isa(dfsub,'TaylorVar'))
          tv=int(dfsub,f);
        else
          dfsub = reshape(dfsub,[],obj.nX);
          tv=TaylorVar(f,{dfsub});
        end
      else
        tv=reshape(f,obj.dim);
      end
    end
    
    function tv = sin(obj)
      tv=elementwise(obj,@sin,@cos);
    end
    function tv = cos(obj)
      tv=elementwise(obj,@cos,inline('-sin(x)','x'));
    end
    
    function tv = diag(v,k)
      % v is a TaylorVar
      if (nargin>1) error('k handling not implemented yet'); end
      if (length(v.dim)>2) error('only for vectors and 2D matrices'); end
      if (v.dim(1)==1 || v.dim(2)==1)  % vector in, create matrix
        n=max(v.dim);
        ind=sub2ind([n,n],1:n,1:n);
        f=diag(v.f);
        for o=1:length(v.df)
          df{o}=sparse(n*n,v.nX^o);
          df{o}(ind,:)=v.df{o};
        end
      else  % matrix in, strip out diagonal vector
        n=min(v.dim);
        ind=sub2ind(v.dim,1:n,1:n);
        f=v.f(ind);
        for o=1:length(v.df)
          df{o}=v.df{o}(ind,:);
        end
      end
      if (exist('df'))
        tv=TaylorVar(f,df);
      else
        tv=f;
      end
    end
    
    function X=mod(X,Y)
      if (isa(Y,'TaylorVar'))
        error('not implemented yet'); % but shouldn't be hard
      else % X is TaylorVar, Y is a const
        X.f = reshape(mod(reshape(X.f,X.dim),Y),[],1);
        % no change to gradients
      end
    end
    
%    function obj=blkdiagcpy(obj,c)
%      if (length(obj.dim)~=2) error('only for 2D matrices'); end
%      m=obj.dim(1);n=obj.dim(2);
%      a=reshape(obj.f,obj.dim);
%      s=sparse([],[],[],m*c,n*c,c*m*n);
%      for i=0:c-1
%        s(i*m+(1:m),i*n+(1:n))=a;
%      end
%      ind=find(s);
%      obj.f=s(:);
%      obj.dim=[m*c,n*c];
%      error('need to finish df terms');
%    end
  end
  
  methods (Static)
    function tv=init(x,order)
      dim=size(x);
      if (length(dim)>2 || dim(2)~=1), error('x must be a column vector'); end  
      n = length(x);
      dx{1} = eye(n);
      for o=2:order
        dx{o} = sparse(n,n^o);
      end
      tv=TaylorVar(x,dx);
    end
  end
  
end

    
